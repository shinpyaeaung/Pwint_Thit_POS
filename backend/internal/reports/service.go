package reports

import (
	"context"
	"encoding/json"
	"fmt"
)

type Repository interface {
	Read(context.Context, string, Filter) ([]byte, error)
}
type Service struct{ repository Repository }

func NewService(repository Repository) *Service { return &Service{repository: repository} }
func (s *Service) Run(ctx context.Context, definition Definition, filter Filter) (Response, error) {
	data, err := s.repository.Read(ctx, definition.ID, filter)
	if err != nil {
		return Response{}, err
	}
	var result Result
	if err = json.Unmarshal(data, &result); err != nil {
		return Response{}, fmt.Errorf("decode report: %w", err)
	}
	return Response{Definition: definition, Filter: filter, Result: result}, nil
}
