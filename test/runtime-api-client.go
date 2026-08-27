package main

import (
	"context"
	"fmt"
	"os"
	"slices"
	"time"

	api "github.com/araihu/dex/api/v2"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	if len(os.Args) != 3 {
		panic("usage: runtime-api-client ADDRESS EXPECTED_SERVER_VERSION")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	conn, err := grpc.NewClient(os.Args[1], grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		panic(err)
	}
	defer conn.Close()
	client := api.NewDexClient(conn)

	version, err := client.GetVersion(ctx, &api.VersionReq{}, grpc.WaitForReady(true))
	must(err)
	if version.GetServer() != os.Args[2] || version.GetApi() != 4 {
		panic(fmt.Sprintf("runtime tuple = (%q, %d)", version.GetServer(), version.GetApi()))
	}

	verified := true
	password := &api.Password{
		Email:             "runtime-profile@example.invalid",
		Hash:              []byte("$2a$10$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W"),
		Username:          "runtime-profile",
		UserId:            "runtime-profile-1",
		Name:              "Runtime Profile",
		PreferredUsername: "runtime-public",
		EmailVerified:     &verified,
		Groups:            []string{"operators", "reviewers"},
	}
	created, err := client.CreatePassword(ctx, &api.CreatePasswordReq{Password: password})
	must(err)
	if created.GetAlreadyExists() {
		panic("runtime password already existed")
	}
	assertListed(ctx, client, password.Email, password.Name, password.PreferredUsername, true, password.Groups)

	empty := ""
	verified = false
	_, err = client.UpdatePassword(ctx, &api.UpdatePasswordReq{
		Email:                password.Email,
		NewName:              &empty,
		NewPreferredUsername: &empty,
		NewEmailVerified:     &verified,
		NewGroups:            &api.PasswordGroups{},
	})
	must(err)
	assertListed(ctx, client, password.Email, "", "", false, nil)
}

func assertListed(ctx context.Context, client api.DexClient, email, name, preferred string, verified bool, groups []string) {
	listed, err := client.ListPasswords(ctx, &api.ListPasswordReq{})
	must(err)
	for _, password := range listed.GetPasswords() {
		if password.GetEmail() != email {
			continue
		}
		if password.GetName() != name || password.GetPreferredUsername() != preferred || password.EmailVerified == nil || password.GetEmailVerified() != verified || !slices.Equal(password.GetGroups(), groups) {
			panic(fmt.Sprintf("listed profile mismatch: %+v", password))
		}
		return
	}
	panic("runtime password not listed")
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
