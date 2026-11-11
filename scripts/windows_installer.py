"""Single Client service + UI MSI. WiX owns install/upgrade transactions."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import uuid
import xml.etree.ElementTree as ET

NS = "http://wixtoolset.org/schemas/v4/wxs"
UPGRADE_CODE = "{FA0F488C-9869-47EC-A2B0-F41313F40657}"
PUBLIC = "O:SYG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FRFX;;;BU)"
PRIVATE = "O:SYG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)"
SERVICE = r"SYSTEM\CurrentControlSet\Services\endlessnet-client"


def identifier(prefix, value):
    return prefix + hashlib.sha256(value.encode()).hexdigest()[:24]


def literal(value):
    # MSI formatted strings and WiX preprocessing have separate escaping.
    return re.sub(r"[\[\]]", lambda m: "[\\" + m[0] + "]", value.replace("$", "$$"))


def render(ui, client, service, policy, actions, version, output):
    if not re.fullmatch(r"v?0\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("Требуется версия v0.MINOR.PATCH")
    ui, client, output = Path(ui).resolve(), Path(client).resolve(), Path(output).resolve()
    if not (ui / "endlessnet_client_ui.exe").is_file() or not all((client / name).is_file() for name in ("client.exe", "wintun.dll", "WINTUN-LICENSE.txt")):
        raise ValueError("Не найдены UI bundle или Client runtime")
    if not Path(actions).is_file():
        raise ValueError("Не собран installer actions DLL")
    if not service or any(not isinstance(k, str) or not k.startswith("ENDLESSNET_CLIENT_") or
                          not isinstance(v, str) or "\0" in k + v or "\n" in k + v or "\r" in k + v
                          for k, v in service.items()):
        raise ValueError("Service profile должен содержать только строковые Client environment values")
    if policy.get("schema") != 1 or "instance_id" in policy:
        raise ValueError("UI policy: schema1 без install-time instance_id")
    if policy.get("profile_id") != service.get("ENDLESSNET_CLIENT_DEFAULT_PROFILE_ID") or policy.get("control_origin") != service.get("ENDLESSNET_CLIENT_CONTROL_ORIGIN"):
        raise ValueError("Default profile Client и UI должны совпадать")
    output.mkdir(parents=True, exist_ok=True)
    policy = dict(policy, server_sid="S-1-5-18")
    policy_file = output / "launch-policy.json"
    policy_file.write_text(json.dumps(policy, ensure_ascii=False), encoding="utf-8")
    ET.register_namespace("", NS)
    root = ET.Element("{" + NS + "}Wix")

    def add(parent, tag, **attrs):
        return ET.SubElement(parent, "{" + NS + "}" + tag, attrs)

    package = add(root, "Package", Name="EndlessNet", Manufacturer="EndlessNet",
                  Version=version.removeprefix("v"), UpgradeCode=UPGRADE_CODE,
                  Scope="perMachine", InstallerVersion="500", Compressed="yes")
    add(package, "MajorUpgrade", Schedule="afterInstallInitialize", DowngradeErrorMessage="Установлена более новая версия EndlessNet.")
    add(package, "MediaTemplate", EmbedCab="yes")
    add(package, "Property", Id="ENDLESSNET_INSTALLATION_ID", Secure="yes")
    add(package, "Property", Id="ENDLESSNET_EXISTING_INSTALLATION", Secure="yes")
    program = add(package, "StandardDirectory", Id="ProgramFiles64Folder")
    app = add(program, "Directory", Id="AppRoot", Name="EndlessNet")
    common = add(package, "StandardDirectory", Id="CommonAppDataFolder")
    data = add(add(common, "Directory", Id="DataVendor", Name="EndlessNet"), "Directory", Id="ClientData", Name="Client")
    state = add(data, "Directory", Id="ClientState", Name="state")
    menu = add(package, "StandardDirectory", Id="ProgramMenuFolder")
    feature = add(package, "Feature", Id="Product", Title="EndlessNet", Level="1")

    def component(directory, name, permanent=False):
        cid = identifier("C", name)
        node = add(directory, "Component", Id=cid, Guid=str(uuid.uuid5(uuid.UUID(UPGRADE_CODE.strip("{}")), name)), Bitness="always64", **({"Permanent": "yes"} if permanent else {}))
        add(feature, "ComponentRef", Id=cid)
        return node

    for directory, name, sddl in [(app, "app", PUBLIC), (data, "data", PUBLIC), (state, "state", PRIVATE)]:
        node = component(directory, "directory:" + name, permanent=name != "app")
        add(add(node, "CreateFolder"), "PermissionEx", Sddl=sddl)

    files = {}
    for source in [ui, client]:
        for path in source.rglob("*"):
            if path.is_symlink():
                raise ValueError("Symlinks не входят в installer inputs")
            if path.is_file():
                relative = path.relative_to(source).as_posix()
                if relative.lower() in files:
                    raise ValueError("Конфликт bundle files: " + relative)
                files[relative.lower()] = (relative, path)
    directories = {"": app}
    for relative, path in sorted(files.values()):
        parent = ""
        for part in Path(relative).parts[:-1]:
            child = parent + "/" + part
            if child not in directories:
                directories[child] = add(directories[parent], "Directory", Id=identifier("D", child), Name=part)
            parent = child
        node = component(directories[parent], relative)
        fid = "ClientExe" if relative == "client.exe" else "UiExe" if relative == "endlessnet_client_ui.exe" else identifier("F", relative)
        add(add(node, "File", Id=fid, Source=str(path), KeyPath="yes"), "PermissionEx", Sddl=PUBLIC)
        if fid == "ClientExe":
            add(node, "ServiceInstall", Id="ClientService", Name="endlessnet-client", DisplayName="EndlessNet Client", Type="ownProcess", Start="auto", ErrorControl="normal", Account="LocalSystem", Arguments="installed-run")
            add(node, "ServiceControl", Id="ClientControl", Name="endlessnet-client", Start="install", Stop="both", Remove="uninstall", Wait="yes")
            env = add(node, "RegistryValue", Root="HKLM", Key=SERVICE, Name="Environment", Type="multiString")
            settings = {key: literal(value) for key, value in service.items()}
            settings.update({"ENDLESSNET_CLIENT_INSTALLATION_ID": "[ENDLESSNET_INSTALLATION_ID]",
                             "ENDLESSNET_CLIENT_SERVICE_SID": "S-1-5-18",
                             "ENDLESSNET_CLIENT_STATE_DIRECTORY": "[CommonAppDataFolder]EndlessNet\\Client\\state",
                             "ENDLESSNET_CLIENT_RUNTIME_INSTANCE_FILE": "[CommonAppDataFolder]EndlessNet\\Client\\runtime-instance"})
            for key, value in sorted(settings.items()):
                add(env, "MultiStringValue", Value=key + "=" + value)
    node = component(data, "machine-id", permanent=True)
    add(node, "RegistryValue", Root="HKLM", Key=r"SOFTWARE\EndlessNet\Client", Name="InstallationId", Type="string", Value="[ENDLESSNET_INSTALLATION_ID]", KeyPath="yes")
    node = component(data, "launch-policy", permanent=True)
    node.set("NeverOverwrite", "yes")
    add(add(node, "File", Id="LaunchPolicy", Source=str(policy_file), KeyPath="yes"), "PermissionEx", Sddl=PUBLIC)
    node = component(menu, "shortcut")
    add(node, "Shortcut", Id="StartMenu", Name="EndlessNet", Target="[#UiExe]", WorkingDirectory="AppRoot", Arguments='--config "[ClientData]launch-policy.json" --runtime-instance "[ClientData]runtime-instance"')
    add(node, "RegistryValue", Root="HKLM", Key=r"SOFTWARE\EndlessNet\Client", Name="Shortcut", Type="integer", Value="1", KeyPath="yes")
    add(package, "Binary", Id="InstallerActions", SourceFile=str(Path(actions).resolve()))
    add(package, "CustomAction", Id="PrepareMachine", BinaryRef="InstallerActions", DllEntry="PrepareMachine", Return="check")
    add(package, "CustomAction", Id="InitializeState", FileRef="ClientExe", ExeCommand="installed-init", Execute="deferred", Impersonate="no", Return="check")
    sequence = add(package, "InstallExecuteSequence")
    add(sequence, "Custom", Action="PrepareMachine", After="CostFinalize", Condition='NOT REMOVE')
    add(sequence, "WriteRegistryValues", Sequence="5810")
    add(sequence, "Custom", Action="InitializeState", After="WriteRegistryValues", Condition='NOT Installed AND NOT ENDLESSNET_EXISTING_INSTALLATION AND NOT REMOVE')
    filename = output / "EndlessNet.wxs"
    ET.ElementTree(root).write(filename, encoding="utf-8", xml_declaration=True)
    return filename


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["ui", "client", "service-profile", "ui-policy", "actions", "version", "output"]:
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    render(args.ui, args.client, json.loads(Path(args.service_profile).read_text(encoding="utf-8")),
           json.loads(Path(args.ui_policy).read_text(encoding="utf-8")), args.actions, args.version, args.output)


if __name__ == "__main__":
    main()
