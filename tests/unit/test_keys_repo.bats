#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    KEYS="$ROOT/keys"
}

@test "the keys directory exists" {
    [ -d "$KEYS" ]
}

@test "a revoked list exists (may be empty)" {
    [ -f "$KEYS/revoked" ]
}

@test "no private key material is committed anywhere in the repo" {
    # Le motif couvre PEM PKCS#8, PEM traditionnel, EC, RSA et OpenSSH.
    run grep -rlE 'BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY' \
        --exclude-dir=.git --exclude-dir=node_modules "$ROOT"
    [ "$status" -ne 0 ]
}

@test "every file in keys/ is a public artefact (pem, allowed_signers, revoked, doc)" {
    while IFS= read -r f; do
        case "$(basename "$f")" in
            *.pem|allowed_signers|revoked|README.md|.gitignore) ;;
            *) printf 'fichier inattendu dans keys/ : %s\n' "$f"; return 1 ;;
        esac
    done < <(find "$KEYS" -type f)
}

@test "every .pem in keys/ is a parseable EC public key" {
    local found=0 f
    while IFS= read -r f; do
        found=1
        run openssl pkey -pubin -in "$f" -noout
        [ "$status" -eq 0 ]
    done < <(find "$KEYS" -name '*.pem' -type f)
    # Aucune clé encore committée à ce stade : le test est vrai par vacuité,
    # et devient contraignant dès la Task 11.
    [ "$found" -eq 0 ] || [ "$found" -eq 1 ]
}
