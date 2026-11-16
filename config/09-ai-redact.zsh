#!/usr/bin/env zsh
# =============================================================================
# AI Core - Secret Redaction
# =============================================================================
# Part of the AI core. Sourced by config/09-ai-core.zsh, which is the entry
# point listed in .zshrc -- this file is not loaded on its own.
#
# Nothing here knows a language. A secret is recognised by the shape of its
# value and of the text around it, never by the word that names it:
#   - an assignment of any kind: `key=value`, `key = "value"`, `key: value`,
#     `"key": "value"`, `--flag=value`, `--flag value`, `export KEY=value`.
#     The key can be written in any language and any script (`contraseña=`,
#     `パスワード：`, `пароль:`, `كلمة_المرور=`): only the `=`/`:` and the
#     separators around it count;
#   - URL userinfo (`scheme://user:secret@host`), an `Authorization:` header,
#     the value of any `-H 'Name: value'` header, `-u user:secret`, `-pSECRET`;
#   - a private-key block (`-----BEGIN ... PRIVATE KEY-----` to its END line,
#     or to the end of the text when the END line was cut off);
#   - the fixed prefixes of provider tokens (the list follows the gitleaks
#     rule set: GitHub, GitLab, Slack, OpenAI, Anthropic, AWS, Google, Stripe,
#     Hugging Face, npm, PyPI, SendGrid, Shopify, DigitalOcean, Vault, age,
#     JWT);
#   - a token-shaped run of 20+ ASCII characters whose entropy is close to
#     that of random text, of 32+ characters mixing digits and letters, or
#     of 20+ hex digits mixing digits and letters.
#
# Trade-off, chosen by the owner: over-redaction is acceptable, a leak is not.
# So the value of an assignment is masked whatever it looks like, except when
# it cannot hold a literal secret: a shell variable reference ($NAME,
# ${NAME}), a path (/..., ~..., ./..., ../...), a URL (its userinfo is masked
# by the URL rule), a number of at most three digits, or an already masked
# value. What this costs, and nothing else:
#   - `LANG=fr_FR.UTF-8`, `--branch main`, `--format="%h %s"` lose their value;
#   - prose loses the word right after `word:` or `word =` -- "Note: ceci"
#     becomes "Note: ***REDACTED***", a conventional commit subject "fix: typo"
#     loses "typo" (but "fix(ai): typo" keeps it: the `)` is not a key);
#   - after a full-width colon no space is needed, so in CJK prose the clause
#     after `：` is masked up to the next space or punctuation that ends a
#     value;
#   - full git SHAs, 20+ character hex strings, UUID-like runs and some
#     identifiers (`python3-venv-requirements`) are masked.
# Ordinary text with no `=`/`:` assignment shape (a sentence in any script, a
# path, a commit message passed with -m, a file name) is never touched.
#
# What cannot be caught: a secret introduced by a word instead of a symbol
# ("the password is hunter2", "パスワードはabc"), when it is too short and too
# regular to look random. No language-independent rule can see it, and a
# keyword list would only see it in the languages it lists. And, with no key
# in front of it, a random run that happens to look regular: measured on
# random tokens of 20-26 characters, about 1 in 20 lower-case+digit tokens
# and 1 in 60 letters-only tokens get through; mixed case with digits, hex,
# and anything of 32+ characters mixing digits and letters, none.
#
# Why not an existing scanner: gitleaks, detect-secrets and trufflehog all
# gate their generic rule on a keyword list (gitleaks: access, api, auth, key,
# credential, creds, passwd, password, secret, token; detect-secrets: the same
# plus `contraseña`), which is the defect being fixed here; they are also a Go
# binary or a Python process per call and report findings rather than rewrite
# text. Their provider prefixes are reused below.
#
# Needs a UTF-8 LC_CTYPE for keys and values outside ASCII to be measured in
# characters; under LC_ALL=C they are matched byte by byte, which still masks
# them.
#
# Two entry points:
#   _ai_redact_text TEXT  -> REPLY: every rule; for data coming from the
#                            person or the system (command lines, history,
#                            file contents, questions).
#   _ai_redact_shapes TEXT -> REPLY: only the rules that cannot fire on a
#                            prompt template written by this code (keys,
#                            prefixes, URLs, headers, entropy); applied by
#                            _ai_api_call to every whole prompt.
# =============================================================================

zmodload zsh/mathfunc   # log(), for the entropy rule

typeset -g _AI_REDACTED='***REDACTED***'

# Characters that end a key or a bare value. Kept as ERE bracket bodies.
typeset -g _AI_RX_KEYCH='[^][:space:]"'"'"'`;&|<>(){}=:：＝,?#]'
typeset -g _AI_RX_VALUE='("[^"'$'\n'']*"|'"'"'[^'"'"$'\n'']*'"'"'|`[^`'$'\n'']*`|[^-=[:space:]"'"'"'`;&|<>][^[:space:]"'"'"'`;&|<>]*)'

# Can value $1 not hold a literal secret? See the trade-off above.
_ai_redact__harmless() {
    emulate -L zsh
    setopt extendedglob
    local v=$1
    if [[ $v == \"*\" || $v == \'*\' || $v == \`*\` ]]; then
        v=${v[2,-2]}
    fi
    [[ -z $v ]] && return 0
    [[ $v == *"$_AI_REDACTED"* ]] && return 0
    [[ $v == (\$[A-Za-z_][A-Za-z0-9_]#|\$\{[A-Za-z_][A-Za-z0-9_]#\}|\$[0-9@*#?!\$-]) ]] && return 0
    [[ $v == (/|\~|./|../)* ]] && return 0
    [[ $v == [A-Za-z][A-Za-z0-9+.-]#://* ]] && return 0
    [[ $v == [0-9](#c1,3) ]] && return 0
    return 1
}

# Rewrite every match of ERE $1 in REPLY with handler $2. The handler reads
# $match (the groups) and sets REPLY to the replacement.
_ai_redact__each() {
    emulate -L zsh
    local re=$1 handler=$2 rest=$REPLY out='' MATCH
    local -i MBEGIN MEND
    local -a match mbegin mend
    while [[ -n $rest && $rest =~ $re ]]; do
        out+=${rest[1,MBEGIN-1]}
        $handler
        out+=$REPLY
        rest=${rest[MEND+1,-1]}
    done
    REPLY=$out$rest
}

# The groups of the assignment rules: everything up to the value, the value.
_ai_redact__mask_value() {
    local value=$match[-1]
    if _ai_redact__harmless "$value"; then
        REPLY=$MATCH
    else
        REPLY=${MATCH[1,-$(( ${#value} + 1 ))]}$_AI_REDACTED
    fi
}

_ai_redact__mask_all() { REPLY=$_AI_REDACTED; }
_ai_redact__keep_head() { REPLY=$match[1]$_AI_REDACTED; }

# Shannon entropy of $1 in bits per character, in REPLY.
_ai_redact__entropy() {
    emulate -L zsh
    local s=$1 c
    local -i n=${#s} k
    local -F h=0 p
    for c in ${(u)${(s::)s}}; do
        k=${#${s//[^${(b)c}]/}}
        p=$(( k * 1.0 / n ))
        h=$(( h - p * log(p) / log(2.0) ))
    done
    REPLY=$h
}

# A token-shaped run (group 2, after the boundary in group 1).
_ai_redact__token() {
    emulate -L zsh
    setopt extendedglob
    local before=$match[1] token=$match[2] segment
    # 32+ characters mixing digits and letters, or 20+ hex digits mixing
    # digits and letters (hex is too small an alphabet for entropy to tell),
    # between slashes.
    for segment in ${(s:/:)token}; do
        if [[ $segment == *[0-9]* && $segment == *[A-Za-z]* ]] &&
           (( ${#segment} >= 32 || ${#segment} >= 20 && ${#${(M)segment:#([0-9a-f]##|[0-9A-F]##)}} )); then
            REPLY=$before$_AI_REDACTED
            return 0
        fi
    done
    # Then entropy (_ai_redact__random).
    # An absolute path is measured one directory at a time: a temporary
    # directory's random suffix must not hide the whole path. (A base64
    # secret starting with `/` -- one in 64 -- is then measured in pieces.)
    local -a pieces=("$token")
    [[ $token == /* ]] && pieces=(${(s:/:)token})
    for segment in $pieces; do
        _ai_redact__random "$segment" && { REPLY=$before$_AI_REDACTED; return 0; }
    done
    REPLY=$MATCH
}

# Does $1 (20+ characters) look like random text? Entropy close to that of
# random text of this length: words, identifiers and paths measure 3.4-3.9
# bits for 16-53 characters, random base62/base64 of 20-40 characters
# 4.0-4.7, against a ceiling of log2(length) bits (4 for hex). The more of upper case,
# lower case and digits a run mixes, the lower the bar: that mix is what
# generated tokens look like, and the identifiers it also catches are an
# accepted over-redaction.
_ai_redact__random() {
    emulate -L zsh
    setopt extendedglob
    local token=$1
    local -i n=${#token}
    (( n >= 20 )) || return 1
    # The most a run can measure is log2 of its length or of the size of the
    # alphabet it is drawn from, whichever is smaller: hex is 16 symbols.
    local -i classes=0 alphabet=64
    [[ $token == *[A-Z]* ]] && (( classes++ ))
    [[ $token == *[a-z]* ]] && (( classes++ ))
    [[ $token == *[0-9]* ]] && (( classes++ ))
    [[ $token == ([0-9a-f]##|[0-9A-F]##) ]] && alphabet=16
    local -F ceiling=$(( log(n < alphabet ? n : alphabet) / log(2.0) ))
    local -F bar=$(( classes == 3 ? 0.78 : classes == 2 ? 0.82 : 0.88 ))
    local REPLY
    _ai_redact__entropy "$token"
    (( REPLY >= bar * ceiling ))
}

# Rules that are safe on a prompt template: they need a value shaped like a
# credential, never just a key.
_ai_redact_shapes() {
    emulate -L zsh
    setopt extendedglob
    REPLY=$1

    # Private-key blocks, to their END line or to the end of the text.
    _ai_redact__each '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----([^-]|-[^-])*(-----END [A-Z0-9 ]*PRIVATE KEY-----)?' _ai_redact__mask_all

    # URL userinfo: scheme://user:secret@host keeps the user.
    REPLY=${REPLY//(#b)([A-Za-z][A-Za-z0-9+.-]#:\/\/[^\/@[:space:]:]#:)[^\/@[:space:]]##@/${match[1]}${_AI_REDACTED}@}

    # Authorization headers (HTTP names, case-insensitive), then the
    # credential after an HTTP auth scheme.
    REPLY=${REPLY//(#bi)((proxy-|)authorization[[:blank:]]#[:=][[:blank:]]#)[^\"\'$'\n']##/${match[1]}${_AI_REDACTED}}
    REPLY=${REPLY//(#b)((Bearer|Basic|Digest)[[:blank:]]##)[A-Za-z0-9._~+\/=-]##/${match[1]}${_AI_REDACTED}}

    # Provider token prefixes, at the start of a token.
    _ai_redact__each '(^|[^A-Za-z0-9_])(gh[pousr]_|github_pat_|glpat-|gldt-|glrt-|glptt-|xox[abposr]-|xapp-|sk-ant-|sk-proj-|sk-|[sr]k_(live|test)_|pk_live_|hf_|npm_|pypi-|AIza|ya29\.|AKIA|ASIA|shp(at|ca|pa|ss)_|do[opr]_v1_|SG\.|hvs\.|AGE-SECRET-KEY-1|eyJ)[A-Za-z0-9_.=+/-]{8,}' _ai_redact__prefix

    # Token-shaped runs.
    # `=` only as trailing base64 padding, so `KEY=token` keeps its key.
    _ai_redact__each '(^|[^A-Za-z0-9_+/-])([A-Za-z0-9_+/-]{20,}=*)' _ai_redact__token
}

_ai_redact__prefix() {
    REPLY=$match[1]$match[2]$_AI_REDACTED
}

# Every rule: for text that comes from the person or the system.
_ai_redact_text() {
    emulate -L zsh
    setopt extendedglob
    local text=$1
    local K=$_AI_RX_KEYCH V=$_AI_RX_VALUE
    # Optional space (or the no-break spaces of French typography) before a
    # colon or an equals sign.
    local S='( | | )?'
    REPLY=$text

    # Run the shape rules first: they know where a credential ends better
    # than the generic value pattern does (an Authorization header value
    # holds a space).
    _ai_redact_shapes "$REPLY"

    # The value of any -H/--header 'Name: value', to the closing quote.
    REPLY=${REPLY//(#b)((-H|--header)[[:blank:]]#([\"\']|)[^:\"\'$'\n']##:[[:blank:]]#)[^\"\'$'\n']##/${match[1]}${_AI_REDACTED}}
    # -u/--user/--proxy-user user:secret keeps the user.
    REPLY=${REPLY//(#b)((-u|--user|--proxy-user)[[:blank:]]##[\"\']#[^:[:space:]\"\']#:)[^[:space:]\"\']##/${match[1]}${_AI_REDACTED}}

    # key=value, key = value, key＝value (any key, any script).
    _ai_redact__each "(${K}+[\"']?)[[:blank:]]*${S}(=|＝)[[:blank:]]*${V}" _ai_redact__mask_value
    # key: value / "key": "value" / key：value. After an ASCII colon a space
    # is required unless the value is quoted (compact JSON), so URLs, times
    # and image:tag are left alone.
    _ai_redact__each "(${K}+[\"']?)(${S}:[[:space:]]+|[\"']:[[:space:]]*|${S}：[[:space:]]*)${V}" _ai_redact__mask_value
    # --flag value (space-separated; --flag=value is an assignment above).
    _ai_redact__each "(--${K}+)[[:blank:]]+${V}" _ai_redact__mask_value
    # -pSECRET (attached short password flag).
    _ai_redact__each "(^|[[:space:]])(-p)([^-[:space:]\"'\`;&|<>][^[:space:]\"'\`;&|<>]{3,})" _ai_redact__mask_value
}

# Filter form: stdin to stdout, every rule.
_ai_redact() {
    emulate -L zsh
    local text REPLY
    text=$(command cat; print -n x)
    _ai_redact_text "${text%x}"
    print -rn -- "$REPLY"
}
