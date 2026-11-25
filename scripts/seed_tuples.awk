{
    output = ""
    for (index_at = 1; index_at <= length($0); index_at++) {
        ch = substr($0, index_at, 1)
        next_ch = substr($0, index_at + 1, 1)
        if (quote != "") {
            if (ch == quote && !escaped) quote = ""
            escaped = quote != "`" && ch == "\\" && !escaped
        } else if (ch == "-" && next_ch == "-") {
            output = output substr($0, index_at)
            break
        } else if (ch == "\"" || ch == "'" || ch == "`") {
            quote = ch
        } else if (ch == "." && next_ch == "(") {
            tuple[++depth] = 1
            output = output ".{"
            index_at++
            continue
        } else if (ch == "(") {
            tuple[++depth] = 0
        } else if (ch == ")") {
            if (tuple[depth]) ch = "}"
            delete tuple[depth--]
        }
        output = output ch
    }
    print output
}
