package products

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"
)

const maxImageBytes = 2 * 1024 * 1024

// Bound decoded image memory even under concurrent authenticated uploads.
var imageSlots = make(chan struct{}, 2)

type productImage struct {
	content           []byte
	contentType, hash string
}

func sanitizeImage(data []byte) (*productImage, error) {
	if len(data) == 0 || len(data) > maxImageBytes {
		return nil, fmt.Errorf("Choose a JPEG or PNG image up to 2 MB.")
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || (format != "jpeg" && format != "png") {
		return nil, fmt.Errorf("Choose a valid JPEG or PNG image.")
	}
	if cfg.Width < 1 || cfg.Height < 1 || cfg.Width > 4096 || cfg.Height > 4096 || int64(cfg.Width)*int64(cfg.Height) > 12000000 {
		return nil, fmt.Errorf("Image dimensions must be at most 4096 pixels per side and 12 megapixels.")
	}
	decoded, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("This image is damaged. Choose another file.")
	}
	// Re-encoding strips metadata and any appended non-image payload.
	var out bytes.Buffer
	if format == "jpeg" {
		err = jpeg.Encode(&out, decoded, &jpeg.Options{Quality: 85})
	} else {
		err = png.Encode(&out, decoded)
	}
	if err != nil || out.Len() > maxImageBytes {
		return nil, fmt.Errorf("The processed image exceeds 2 MB. Choose a smaller image.")
	}
	hash := sha256.Sum256(out.Bytes())
	return &productImage{out.Bytes(), "image/" + format, hex.EncodeToString(hash[:])}, nil
}

// Streaming multipart parsing never spills uploaded files onto the server disk.
func decodeProduct(c *gin.Context, in *Input) (*productImage, bool) {
	if c.ContentType() != "multipart/form-data" {
		return nil, decode(c, in)
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 3*1024*1024)
	reader, err := c.Request.MultipartReader()
	if err != nil {
		fail(c, 400, "Invalid image upload.")
		return nil, false
	}
	var data []byte
	seen := map[string]bool{}
	for {
		part, e := reader.NextPart()
		if e == io.EOF {
			break
		}
		if e != nil {
			fail(c, 400, "Invalid or oversized image upload.")
			return nil, false
		}
		name := part.FormName()
		if seen[name] || (name != "product" && name != "image") {
			fail(c, 400, "Supply one product and at most one image.")
			return nil, false
		}
		seen[name] = true
		limit := maxImageBytes
		if name == "product" {
			limit = 64 * 1024
		}
		content, e := io.ReadAll(io.LimitReader(part, int64(limit)+1))
		if e != nil || len(content) > limit {
			fail(c, 413, "Product data or image is too large. Images must be up to 2 MB.")
			return nil, false
		}
		if name == "product" {
			d := json.NewDecoder(bytes.NewReader(content))
			d.DisallowUnknownFields()
			if d.Decode(in) != nil || d.Decode(new(any)) != io.EOF {
				fail(c, 400, "Invalid product fields.")
				return nil, false
			}
		} else {
			data = content
		}
	}
	if !seen["product"] || (seen["image"] && in.RemoveImage) {
		fail(c, 400, "Supply product data and either replace or remove its image.")
		return nil, false
	}
	if !seen["image"] {
		return nil, true
	}
	select {
	case imageSlots <- struct{}{}:
		defer func() { <-imageSlots }()
	case <-c.Request.Context().Done():
		fail(c, 408, "Image upload timed out.")
		return nil, false
	}
	img, err := sanitizeImage(data)
	if err != nil {
		fail(c, 400, err.Error())
		return nil, false
	}
	return img, true
}

func (s *Service) Image(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	img, err := s.q.GetProductImage(c.Request.Context(), id)
	if err != nil {
		dbError(c, err)
		return
	}
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Cache-Control", "private, no-store")
	c.Data(http.StatusOK, img.ContentType, img.Content)
}
