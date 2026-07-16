package serviceemulator

import (
	"context"
	"errors"
)

var ErrUnsupportedPlatform = errors.New("the EndlessNet service emulator named pipe is supported only on Windows")

type Server struct {
	PipePath       string
	Engine         *Engine
	MaxBodyBytes   int64
	Ready          chan struct{}
	RequestStarted func()
}

func (s *Server) Serve(ctx context.Context) error {
	if s.Engine == nil {
		return errors.New("service emulator engine is required")
	}
	if s.MaxBodyBytes <= 0 {
		s.MaxBodyBytes = DefaultMaxBodyBytes
	}
	if s.Ready == nil {
		s.Ready = make(chan struct{})
	}
	return serveNamedPipe(ctx, s)
}
