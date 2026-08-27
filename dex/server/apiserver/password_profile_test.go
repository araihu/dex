package apiserver

import (
	"slices"
	"testing"

	api "github.com/dexidp/dex/api/v2"
	"github.com/dexidp/dex/storage/memory"
)

func TestPasswordProfileFieldsRoundTrip(t *testing.T) {
	logger := newLogger(t)
	store := memory.New(logger)
	client := newAPI(t, store, logger)
	t.Cleanup(client.Close)

	ctx := t.Context()
	emailVerified := false
	password := &api.Password{
		Email:             "profile@example.com",
		Hash:              []byte("$2a$10$XVMN/Fid.Ks4CXgzo8fpR.iU1khOMsP5g9xQeXuBm1wXjRX8pjUtO"),
		Username:          "profile",
		UserId:            "profile-123",
		Name:              "Profile User",
		PreferredUsername: "profile-public",
		EmailVerified:     &emailVerified,
		Groups:            []string{"developers", "operators"},
	}

	created, err := client.CreatePassword(ctx, &api.CreatePasswordReq{Password: password})
	if err != nil {
		t.Fatalf("create password: %v", err)
	}
	if created.GetAlreadyExists() {
		t.Fatal("password unexpectedly already existed")
	}

	stored, err := store.GetPassword(ctx, password.Email)
	if err != nil {
		t.Fatalf("get created password: %v", err)
	}
	if stored.Name != password.Name || stored.PreferredUsername != password.PreferredUsername {
		t.Fatalf("created profile mismatch: got name=%q preferred_username=%q", stored.Name, stored.PreferredUsername)
	}
	if stored.EmailVerified == nil || *stored.EmailVerified {
		t.Fatalf("created email_verified mismatch: got %v", stored.EmailVerified)
	}
	if !slices.Equal(stored.Groups, password.Groups) {
		t.Fatalf("created groups mismatch: got %v want %v", stored.Groups, password.Groups)
	}

	listed, err := client.ListPasswords(ctx, &api.ListPasswordReq{})
	if err != nil {
		t.Fatalf("list passwords: %v", err)
	}
	if len(listed.GetPasswords()) != 1 {
		t.Fatalf("listed password count: got %d want 1", len(listed.GetPasswords()))
	}
	got := listed.GetPasswords()[0]
	if got.GetName() != password.Name || got.GetPreferredUsername() != password.PreferredUsername {
		t.Fatalf("listed profile mismatch: got name=%q preferred_username=%q", got.GetName(), got.GetPreferredUsername())
	}
	if got.EmailVerified == nil || got.GetEmailVerified() {
		t.Fatalf("listed email_verified mismatch: got %v", got.EmailVerified)
	}
	if !slices.Equal(got.GetGroups(), password.Groups) {
		t.Fatalf("listed groups mismatch: got %v want %v", got.GetGroups(), password.Groups)
	}

	emptyName := ""
	preferredUsername := "profile-updated"
	emailVerified = true
	updatedGroups := []string{"reviewers"}
	updated, err := client.UpdatePassword(ctx, &api.UpdatePasswordReq{
		Email:                password.Email,
		NewName:              &emptyName,
		NewPreferredUsername: &preferredUsername,
		NewEmailVerified:     &emailVerified,
		NewGroups:            &api.PasswordGroups{Groups: updatedGroups},
	})
	if err != nil {
		t.Fatalf("update password profile: %v", err)
	}
	if updated.GetNotFound() {
		t.Fatal("password unexpectedly not found")
	}

	stored, err = store.GetPassword(ctx, password.Email)
	if err != nil {
		t.Fatalf("get updated password: %v", err)
	}
	if stored.Name != "" || stored.PreferredUsername != preferredUsername {
		t.Fatalf("updated profile mismatch: got name=%q preferred_username=%q", stored.Name, stored.PreferredUsername)
	}
	if stored.EmailVerified == nil || !*stored.EmailVerified {
		t.Fatalf("updated email_verified mismatch: got %v", stored.EmailVerified)
	}
	if !slices.Equal(stored.Groups, updatedGroups) {
		t.Fatalf("updated groups mismatch: got %v want %v", stored.Groups, updatedGroups)
	}
	if stored.Username != password.Username || !slices.Equal(stored.Hash, password.Hash) {
		t.Fatal("profile update changed existing username or hash")
	}

	emptyPreferredUsername := ""
	emailVerified = false
	if _, err := client.UpdatePassword(ctx, &api.UpdatePasswordReq{
		Email:                password.Email,
		NewPreferredUsername: &emptyPreferredUsername,
		NewEmailVerified:     &emailVerified,
		NewGroups:            &api.PasswordGroups{},
	}); err != nil {
		t.Fatalf("clear password profile: %v", err)
	}
	stored, err = store.GetPassword(ctx, password.Email)
	if err != nil {
		t.Fatalf("get cleared password: %v", err)
	}
	if stored.PreferredUsername != "" || stored.EmailVerified == nil || *stored.EmailVerified || len(stored.Groups) != 0 {
		t.Fatalf("cleared profile mismatch: preferred_username=%q email_verified=%v groups=%v", stored.PreferredUsername, stored.EmailVerified, stored.Groups)
	}
}

func TestCreatePasswordWithoutEmailVerifiedPreservesLegacyDefault(t *testing.T) {
	logger := newLogger(t)
	store := memory.New(logger)
	client := newAPI(t, store, logger)
	t.Cleanup(client.Close)

	password := &api.Password{
		Email:    "legacy@example.com",
		Hash:     []byte("$2a$10$XVMN/Fid.Ks4CXgzo8fpR.iU1khOMsP5g9xQeXuBm1wXjRX8pjUtO"),
		Username: "legacy",
		UserId:   "legacy-123",
	}
	if _, err := client.CreatePassword(t.Context(), &api.CreatePasswordReq{Password: password}); err != nil {
		t.Fatalf("create legacy password: %v", err)
	}

	stored, err := store.GetPassword(t.Context(), password.Email)
	if err != nil {
		t.Fatalf("get legacy password: %v", err)
	}
	if stored.EmailVerified != nil {
		t.Fatalf("omitted email_verified became explicit: %v", stored.EmailVerified)
	}
}
