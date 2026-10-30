package products

import (
	"bytes"
	"image"
	"image/png"
	"testing"
)

func TestSanitizeImage(t *testing.T) {
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewNRGBA(image.Rect(0, 0, 4, 4))); err != nil {
		t.Fatal(err)
	}
	original := append([]byte{}, b.Bytes()...)
	img, err := sanitizeImage(append(b.Bytes(), []byte("untrusted trailing payload")...))
	if err != nil || img.contentType != "image/png" || len(img.hash) != 64 || !bytes.Equal(img.content, original) {
		t.Fatalf("sanitize: %v", err)
	}
	for _, data := range [][]byte{nil, []byte("<svg/>"), original[:len(original)/2], make([]byte, maxImageBytes+1)} {
		if _, err := sanitizeImage(data); err == nil {
			t.Fatal("invalid image accepted")
		}
	}
	b.Reset()
	if err := png.Encode(&b, image.NewGray(image.Rect(0, 0, 4097, 1))); err != nil {
		t.Fatal(err)
	}
	if _, err := sanitizeImage(b.Bytes()); err == nil {
		t.Fatal("oversized dimensions accepted")
	}
}
