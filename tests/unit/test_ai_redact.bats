#!/usr/bin/env bats

# Secret redaction (config/09-ai-redact.zsh), run in a real zsh. Nothing here
# depends on the language of a key: the cases below name the secret in seven
# languages, in four scripts, and not at all. The fixtures are built at run
# time, so no credential-shaped literal sits in the repository.

setup() {
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
    export LANG=C.UTF-8
    unset LC_ALL LC_CTYPE
}

# redact TEXT: run _ai_redact_text in zsh, output in $output.
redact() {
    run zsh -fc 'source "$1/config/09-ai-core.zsh"; _ai_redact_text "$2"; print -rn -- "$REPLY"' \
        zsh "$NIVUUS_SHELL_DIR" "$1"
    [ "$status" -eq 0 ]
}

# masked TEXT SECRET KEPT: SECRET is gone, KEPT (the key) is still there.
masked() {
    redact "$1"
    if [[ "$output" == *"$2"* || "$output" != *"$3"* || "$output" != *'***REDACTED***'* ]]; then
        printf 'input:  %s\noutput: %s\n' "$1" "$output" >&2
        return 1
    fi
}

# kept TEXT: comes back byte for byte.
kept() {
    redact "$1"
    if [[ "$output" != "$1" ]]; then
        printf 'input:  %s\noutput: %s\n' "$1" "$output" >&2
        return 1
    fi
}

@test "a short secret is masked whatever the language of its key" {
    masked 'mot_de_passe=soleil42' soleil42 mot_de_passe=
    masked 'contraseña=girasol7 && ls' girasol7 'contraseña='
    masked 'Passwort: Sonne77' Sonne77 'Passwort:'
    masked 'パスワード=taiyou9' taiyou9 'パスワード='
    masked 'كلمة_المرور=shams3' shams3 'كلمة_المرور='
    masked 'пароль: solnce5' solnce5 'пароль:'
}

@test "a secret written outside ASCII is masked as a whole" {
    masked 'contraseña=ñandú7' 'ñandú' 'contraseña='
    masked 'パスワード=秘密の値' '秘密' 'パスワード='
    masked 'كلمة_المرور=سر١٢٣' 'سر' 'كلمة_المرور='
    masked 'export ПАРОЛЬ="два слова"' 'слова' 'export ПАРОЛЬ='
}

@test "every assignment shape is recognised, not only key=value" {
    masked 'パスワード：hikari' hikari 'パスワード：'
    masked 'mot de passe : soleil' soleil 'mot de passe :'
    # French typography: a narrow no-break space before the colon.
    masked "mot de passe"$'\u202f'": soleil" soleil 'mot de passe'
    masked '{"contraseña":"girasol","n":1}' girasol '"contraseña":'
    masked "  clave: 'girasol'" girasol '  clave:'
    masked 'Kennwort = "zwei Worte"' Worte 'Kennwort = '
    masked 'cmd --mot-de-passe=soleil' soleil '--mot-de-passe='
    masked 'cmd --clave girasol --verbose' girasol '--verbose'
    masked 'mysql -u root -psoleil42 base' soleil42 'mysql -u root -p'
    masked 'curl -u admin:soleil https://x.example' soleil 'admin:'
    masked "curl -H 'X-Jeton: abc12' https://intra.example" abc12 "X-Jeton: "
    masked 'curl -H "Authorization: Basic YWJjOmRlZg" x' YWJj 'Authorization: '
    masked 'git clone https://bob:soleil@git.example/r.git' soleil 'https://bob:'
    masked 'see https://x.example/a?q=1&jeton=abc12&lang=fr' abc12 'jeton='
}

@test "a secret with no key at all is masked by its shape" {
    local prefix_token entropy_token
    prefix_token="gh""p_$(printf 'a%.0s' {1..36})"
    entropy_token="$(printf '%s' wJalrXUtnFEMI K7MDENG bPxRfiCYEXAMPLEKEY | tr -d '\n')"
    masked "git push $prefix_token" "$prefix_token" 'git push '
    masked "aws # $entropy_token" "$entropy_token" 'aws # '
    masked "$(printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----\nafter')" \
        'b3BlbnNzaC1rZXktdjEAAAAA' 'after'
    # Cut before its END line (git diff | head): masked to the end.
    masked "$(printf -- 'x\n-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA\nqwerty')" 'qwerty' 'x'
}

@test "random tokens of 20 to 40 characters are all masked" {
    # Seeded, so the same 200 tokens every run: mixed case and digits, and
    # hex.
    run zsh -fc '
source "$1/config/09-ai-core.zsh"
local -i i j leaks=0
local t chars
RANDOM=4242
for i in {1..200}; do
    chars=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
    (( i % 4 )) || chars=0123456789abcdef
    t=
    for j in {1..$(( 20 + i % 21 ))}; do t+=${chars[RANDOM % ${#chars} + 1]}; done
    _ai_redact_text "x $t y"
    [[ $REPLY == "x ***REDACTED*** y" ]] || { print -r -- "leak: $t"; (( leaks++ )); }
done
exit $leaks' zsh "$NIVUUS_SHELL_DIR"
    [ "$status" -eq 0 ]
}

@test "ordinary text in any language is left untouched" {
    kept 'Le café de l’été coûte 3 € à Zürich, n’est-ce pas ?'
    kept '¿Dónde está la estación? Mañana a las 9.'
    kept 'Die Größe ändern, bitte nicht vergessen.'
    kept '東京駅で待ち合わせ。明日は雨です。'
    kept 'مرحبا بالعالم، كيف حالك؟'
    kept 'Привет, мир! Это обычное предложение.'
    kept 'שלום עולם'
}

@test "paths, commit messages and ordinary command lines are left untouched" {
    kept '/home/élise/Документы/東京/notes.txt'
    kept '~/projets/été/rapport final.pdf'
    kept "git commit -m \"corrige l'affichage du titre en japonais\""
    kept '0a40901 fix(autoupdate): verify provenance, stage and swap atomically'
    kept 'cd ~/projets/été && grep 東京 notes.txt # مرحبا sha 1a2b'
    kept 'docker run --rm -it ubuntu:24.04 bash'
    kept 'if [[ $a == b ]]; then x=$HOME; y=${PATH}; z=/tmp/a; n=12; fi'
    kept 'rendez-vous à 12:30, https://example.com/a/b'
    kept 'ConfigurationManagerFactory src/components/MyComponent2.tsx'
}

@test "the documented over-redaction: the word after word: or word= goes" {
    redact 'Note: ceci est une phrase'
    [ "$output" = 'Note: ***REDACTED*** est une phrase' ]
    redact 'LANG=fr_FR.UTF-8 ls'
    [ "$output" = 'LANG=***REDACTED*** ls' ]
}

@test "redaction is idempotent" {
    local text='contraseña=girasol7 Authorization: Bearer abc123 https://bob:x@h -psoleil42'
    run zsh -fc 'source "$1/config/09-ai-core.zsh"; _ai_redact_text "$2"; local once=$REPLY; _ai_redact_text "$once"; [[ $REPLY == $once ]]' \
        zsh "$NIVUUS_SHELL_DIR" "$text"
    [ "$status" -eq 0 ]
}

@test "under LC_ALL=C a non-ASCII key and value are still masked" {
    run env LC_ALL=C zsh -fc 'source "$1/config/09-ai-core.zsh"; _ai_redact_text "$2"; print -rn -- "$REPLY"' \
        zsh "$NIVUUS_SHELL_DIR" 'パスワード=秘密の値 ok'
    [ "$output" = 'パスワード=***REDACTED*** ok' ]
}

@test "the whole-prompt pass leaves a prompt's own instructions alone" {
    local template='Respond with ONLY: {"found": false}
  "package": "<exact package name, nothing else>",
Missing command: "zzq"'
    run zsh -fc 'source "$1/config/09-ai-core.zsh"; _ai_redact_shapes "$2"; print -rn -- "$REPLY"' \
        zsh "$NIVUUS_SHELL_DIR" "$template"
    [ "$output" = "$template" ]
}
