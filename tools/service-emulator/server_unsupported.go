//go:build !windows

package serviceemulator

import "context"

func serveNamedPipe(context.Context, *Server) error {
	return ErrUnsupportedPlatform
}
