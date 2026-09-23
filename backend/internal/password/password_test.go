package password

import "testing"

func TestHash(t *testing.T) {
	secret := "a long test password 🔑"
	a, err := Hash(secret)
	if err != nil {
		t.Fatal(err)
	}
	b, err := Hash(secret)
	if err != nil {
		t.Fatal(err)
	}
	if a == b {
		t.Fatal("salt reused")
	}
	if !Verify(secret, a) || Verify("wrong", a) || Verify(secret, "broken") {
		t.Fatal("password verification failed")
	}
	if _, err := Hash("short"); err == nil {
		t.Fatal("weak password accepted")
	}
	if Verify("irrelevant", DummyHash) {
		t.Fatal("dummy hash accepted password")
	}
}
