# Contributing

By contributing, you agree that your contribution is licensed under
Apache-2.0 and that you have the right to submit it.

Before opening a pull request:

```powershell
go test ./...
Push-Location app
flutter analyze
flutter test
Pop-Location
```

Keep the UI/runtime boundary intact: communicate with the protected local named
pipe and do not copy runtime source or consume private backend state. Sign off
commits with `git commit -s`.
