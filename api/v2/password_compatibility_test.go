package api

import (
	"testing"

	"google.golang.org/protobuf/reflect/protoreflect"
)

func TestPasswordFieldsPreserveWireNumbers(t *testing.T) {
	assertFieldNumbers(t, (&Password{}).ProtoReflect().Descriptor(), map[protoreflect.Name]protoreflect.FieldNumber{
		"email":              1,
		"hash":               2,
		"username":           3,
		"user_id":            4,
		"name":               5,
		"preferred_username": 6,
		"email_verified":     7,
		"groups":             8,
	})
	assertFieldNumbers(t, (&UpdatePasswordReq{}).ProtoReflect().Descriptor(), map[protoreflect.Name]protoreflect.FieldNumber{
		"email":                  1,
		"new_hash":               2,
		"new_username":           3,
		"new_name":               4,
		"new_preferred_username": 5,
		"new_email_verified":     6,
		"new_groups":             7,
	})
}

func TestPasswordUpdateFieldsPreservePresence(t *testing.T) {
	password := (&Password{}).ProtoReflect().Descriptor().Fields()
	emailVerified := password.ByName("email_verified")
	if emailVerified == nil {
		t.Fatal("Password.email_verified missing")
	}
	if !emailVerified.HasPresence() {
		t.Fatal("Password.email_verified must distinguish omitted from false")
	}

	update := (&UpdatePasswordReq{}).ProtoReflect().Descriptor().Fields()
	for _, name := range []protoreflect.Name{"new_name", "new_preferred_username", "new_email_verified", "new_groups"} {
		field := update.ByName(name)
		if field == nil {
			t.Errorf("UpdatePasswordReq.%s missing", name)
			continue
		}
		if !field.HasPresence() {
			t.Fatalf("UpdatePasswordReq.%s must distinguish no update from an explicit value", name)
		}
	}
}

func assertFieldNumbers(t *testing.T, message protoreflect.MessageDescriptor, want map[protoreflect.Name]protoreflect.FieldNumber) {
	t.Helper()
	fields := message.Fields()
	for name, number := range want {
		field := fields.ByName(name)
		if field == nil {
			t.Errorf("%s.%s missing", message.Name(), name)
			continue
		}
		if field.Number() != number {
			t.Errorf("%s.%s field number = %d, want %d", message.Name(), name, field.Number(), number)
		}
	}
}
