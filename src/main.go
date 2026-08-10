package main

import (
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"flag"
	"log"
	"net/http"
	"os"
	"strings"

	_ "modernc.org/sqlite"
)

func secretHash(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func loadFile(path string) (string, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	return string(data), true
}

func getPage(db *sql.DB, name, tokenHash string) (string, bool) {
	var content string
	err := db.QueryRow("SELECT CONTENT FROM PAGES WHERE NAME=? AND TOKEN=?", name, tokenHash).Scan(&content)
	if err != nil {
		return "", false
	}
	return content, true
}

func editPage(db *sql.DB, name, tokenHash, content string) error {
	_, err := db.Exec(
		`INSERT INTO PAGES(NAME, TOKEN, CONTENT) VALUES(?, ?, ?)
		 ON CONFLICT(NAME) DO UPDATE SET CONTENT=EXCLUDED.CONTENT, TOKEN=EXCLUDED.TOKEN`,
		name, tokenHash, content,
	)
	return err
}

func main() {
	secret, ok := os.LookupEnv("SECRET_HASH")
	if !ok {
		log.Fatal("Fatal: SECRET_HASH must be not None")
	}
	if _, err := hex.DecodeString(secret); err != nil || len(secret) != sha256.Size*2 {
		log.Fatal("SECRET_HASH must be a sha256 hex digest (64 hex characters)")
	}

	addr := flag.String("addr", "localhost:7819", "address:port")
	dbPath := flag.String("db", "pages.db", "SQLite database path")
	adminRoute := flag.String("admin", "/change", "route to change pages")
	flag.Parse()

	if !strings.HasPrefix(*adminRoute, "/") {
		log.Fatal("admin route flag must start with '/'")
	}

	db, err := sql.Open("sqlite", *dbPath+"?_pragma=busy_timeout(5000)")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	_, err = db.Exec("CREATE TABLE IF NOT EXISTS PAGES(NAME VARCHAR(36) UNIQUE PRIMARY KEY, TOKEN VARCHAR(64), CONTENT TEXT)")
	if err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			content, ok := loadFile("login.html")
			if !ok {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Write([]byte(content))
		case http.MethodPost:
			content, ok := getPage(db, r.FormValue("page"), secretHash(r.FormValue("secret")))
			if !ok {
				notFound, ok := loadFile("404.html")
				if !ok {
					http.NotFound(w, r)
					return
				}
				w.Header().Set("Content-Type", "text/html; charset=utf-8")
				w.WriteHeader(http.StatusNotFound)
				w.Write([]byte(notFound))
				return
			}
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Write([]byte(content))
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	})

	mux.HandleFunc(*adminRoute, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		got := secretHash(r.FormValue("secret"))
		if subtle.ConstantTimeCompare([]byte(got), []byte(secret)) != 1 {
			w.WriteHeader(http.StatusConflict)
			return
		}
		err := editPage(db, r.FormValue("page_name"), secretHash(r.FormValue("token")), r.FormValue("content"))
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	})

	log.Fatal(http.ListenAndServe(*addr, mux))
}
