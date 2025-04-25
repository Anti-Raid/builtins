--!nocheck

-- TODO: Write a better parser for URLs later on

-- Helper function: trim_end_except_slash
local function trim_end_except_slash(s: string)
    local punctuation = "!\"#$%%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    local i = #s
    while i > 0 do
        local ch = s:sub(i, i)
        -- Check if ch is a punctuation character (using plain find) and not '/'
        if ch ~= "/" and punctuation:find(ch, 1, true) then
            i = i - 1
        else
            break
        end
    end
    return s:sub(1, i)
end

-- Helper function: trim_end_basic
local function trim_end_basic(s: string)
    local trim_chars = ".,!:; &*@^`$=#%%+?|<>"  -- note: space is included if needed, but original does not include space trimming here
    local i = #s
    while i > 0 do
        local ch = s:sub(i, i)
        if trim_chars:find(ch, 1, true) then
            i = i - 1
        else
            break
        end
    end
    return s:sub(1, i)
end

-- Helper function: trim_start_non_alnum
local function trim_start_non_alnum(s: string)
    local i = 1
    while i <= #s do
        local ch = s:sub(i, i)
        if not ch:match("%w") then
            i = i + 1
        else
            break
        end
    end
    return s:sub(i)
end

-- Function: is_valid_label
local function is_valid_label(label: string)
    -- !label.is_empty() &&
    if label == "" then
        return false
    end
    -- !label.starts_with('-') &&
    if label:sub(1,1) == "-" then
        return false
    end
    -- !label.ends_with('-') &&
    if label:sub(-1) == "-" then
        return false
    end
    -- label.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
    for i = 1, #label do
        local c = label:sub(i,i)
        if not (c:match("%w") or c == "-") then
            return false
        end
    end
    return true
end

-- Function: is_valid_tld
local function is_valid_tld(tld: string)
    -- tld.len() > 1 && tld.chars().all(|c| c.is_ascii_alphabetic())
    if #tld <= 1 then
        return false
    end
    for i = 1, #tld do
        local c = tld:sub(i,i)
        if not c:match("%a") then
            return false
        end
    end
    return true
end

-- Function: find_valid_domain
local function find_valid_domain(s: string): string?
    local labels = {}
    local start = 1
    local len = #s
    local i = 1
    while i <= len do
        local c = s:sub(i,i)
        if c == "." then
            if i == start then
                -- Leading dot or consecutive dots
                return nil
            end
            local label = s:sub(start, i - 1)
            if not is_valid_label(label) then
                return nil
            end
            table.insert(labels, label)
            start = i + 1
        elseif not (c:match("%w") or c == "-") then
            -- Stop at port, path, or invalid character
            break
        end
        i = i + 1
    end
    -- Handle the last label
    if start <= #s then
        local last_label = s:sub(start)
        if is_valid_label(last_label) then
            table.insert(labels, last_label)
        end
    end
    if #labels >= 2 and is_valid_tld(labels[#labels]) then
        return s
    else
        return nil
    end
end

-- Function: extract_query_embedded_url
local function extract_query_embedded_url(segment: string): string?
    local protocols = {"https://", "http://", "ftp://", "git://"}
    local max_end = 0

    for _, proto in ipairs(protocols) do
        local pos = segment:find(proto, 1, true)
        if pos then
            local rest = segment:sub(pos)
            local url_end = nil
            -- Find first whitespace or ) or ! or ] or (
            for j = 1, #rest do
                local ch = rest:sub(j,j)
                if ch:match("%s") or ch == ")" or ch == "!" or ch == "]" or ch == "(" then
                    url_end = j - 1
                    break
                end
            end
            if not url_end then
                url_end = #rest
            end
            max_end = pos + (url_end :: number) - 1
            break
        end
    end

    if max_end > 0 then
        return segment:sub(1, max_end)
    else
        return nil
    end
end

-- Function: find_domain
local function find_domain(s: string): string?
    local path_start = s:find("[/?#]", 1) :: number
    if not path_start then
        path_start = #s + 1
    end
    local domain_port = s:sub(1, path_start - 1)
    local colon_pos = domain_port:find(":", 1, true)
    if colon_pos then
        local domain_part = domain_port:sub(1, colon_pos - 1)
        local port_part = domain_port:sub(colon_pos + 1)
        local domain = find_valid_domain(domain_part)
        if domain then
            local valid_port = true
            if port_part == "" then
                valid_port = false
            else
                for i = 1, #port_part do
                    local c = port_part:sub(i,i)
                    if not c:match("%d") then
                        valid_port = false
                        break
                    end
                end
            end
            if valid_port then
                return s:sub(1, path_start - 1)
            else
                return domain
            end
        else
            return nil
        end
    else
        if find_valid_domain(domain_port) then
            return s:sub(1, path_start - 1)
        else
            return nil
        end
    end
end

-- Function: extract_scheme_less_urls
local function extract_scheme_less_urls(segment: string): {string}
    local urls: {string} = {}
    local i = 1 
    local seg_len = #segment

    while i <= seg_len do
        local potential_end = seg_len - i + 1
        for j = i, seg_len do
            local ch = segment:sub(j, j)
            if not (ch:match("%w") or ch == "." or ch == "-" or ch == ":" or ch == "/" or ch == "?" or ch == "&" or ch == "=" or ch == "#" or ch == "%") then
                potential_end = j - i
                break
            end
        end

        local potential_url = segment:sub(i, i + potential_end - 1) :: string
        potential_url = trim_start_non_alnum(potential_url)

        if potential_url ~= "" then
            local domain = find_domain(potential_url)
            if domain then
                local domain_end = #domain
                local url_to_push = ""
                if domain_end < #potential_url then
                    local next_char = potential_url:sub(domain_end + 1, domain_end + 1)
                    if next_char == "/" or next_char == "?" or next_char == "#" or next_char == "=" then
                        url_to_push = potential_url
                    else
                        url_to_push = potential_url:sub(1, domain_end)
                    end
                else
                    url_to_push = domain
                end

                local url_len = #url_to_push

                -- Check for query-embedded urls (e.g., url=https://target.com)
                if url_to_push:find("?", 1, true) or url_to_push:find("=", 1, true) then
                    local extra = extract_query_embedded_url(segment:sub(i + url_len))
                    if extra then
                        url_len = url_len + #extra
                        url_to_push = segment:sub(i, i + url_len - 1)
                    end
                end

                local cleaned_url = trim_end_basic(url_to_push)
                table.insert(urls, cleaned_url)
                i = (i :: number) + url_len
            else
                if potential_end < 1 then
                    potential_end = 1
                end
                i = i + math.max(potential_end, 1)
            end
        else
            i = i + 1
        end
    end
    return urls
end

-- Function: parse_urls
local function parse_urls(input: string)
    local protocols = {"https://", "http://", "ftp://", "git://"}
    local urls = {}
    local i = 1
    local input_len = #input

    while i <= input_len do
        local next_protocol = nil
        for _, protocol in ipairs(protocols) do
            local pos = input:find(protocol, i, true)
            if pos then
                local abs_pos = pos
                if not next_protocol or abs_pos < next_protocol[1] then
                    next_protocol = {abs_pos, protocol}
                end
            end
        end

        if next_protocol then
            local p = next_protocol[1]
            local protocol = next_protocol[2]
            local segment = input:sub(i, p - 1)
            local scheme_less_urls = extract_scheme_less_urls(segment)
            for _, url in ipairs(scheme_less_urls) do
                table.insert(urls, url)
            end

            local start_index = p + #protocol
            local remaining: string = input:sub(start_index)
            local end_offset = nil
            for j = 1, #remaining do
                local ch = remaining:sub(j,j)
                if ch:match("%s") or ch == ")" or ch == "!" or ch == "]" or ch == "(" then
                    end_offset = j - 1
                    break
                end
            end
            if not end_offset then
                end_offset = #remaining
            end

            local url = input:sub(p, start_index + end_offset - 1)

            -- Check for embedded protocol and split smartly
            local split_found = false
            for _, proto in ipairs(protocols) do
                local search_start = protocol:len() + 1
                local inner_search = url:sub(search_start)
                local inner_pos = inner_search:find(proto, 1, true)
                if inner_pos then
                    local split_at = protocol:len() + inner_pos
                    local preceding_index = split_at - 1
                    local preceding_char = url:sub(preceding_index, preceding_index)
                    if preceding_char == "." or preceding_char:match("%s") or preceding_char:match("%p") then
                        local first = url:sub(1, split_at - 1)
                        first = trim_end_except_slash(first)
                        local second = url:sub(split_at)
                        second = trim_end_except_slash(second)
                        table.insert(urls, first)
                        table.insert(urls, second)
                        i = p + split_at
                        split_found = true
                        break
                    end
                end
            end

            if not split_found then
                -- Ensure IPv6 addresses are correctly handled
                if url:sub(1, 8) == "http://[" and url:sub(-1) ~= "]" then
                    local rem_sub = remaining:sub(1, end_offset)
                    local closing_bracket_pos = rem_sub:find("]", 1, true)
                    if closing_bracket_pos then
                        url = input:sub(p, start_index + closing_bracket_pos - 1)
                    end
                end
                url = trim_end_basic(url)
                table.insert(urls, url)
                i = start_index + end_offset
            end
        else
            local segment = input:sub(i)
            local scheme_less_urls = extract_scheme_less_urls(segment)
            for _, url in ipairs(scheme_less_urls) do
                table.insert(urls, url)
            end
            break
        end
    end

    return urls
end

-- Main function
if(_G._TEST_ASYNC_WORK ~= nil) then
    local function main()
        local input = "discordhttps://real.com random text https://discord.gg/8PmaCxnS ftp://some-server.example-site.org more http://192.168.1.1 text sub.domain.co.uk and path.https://google.com git://netsocialoss discord.gg/acnh is the best.https://google.com/best ||spoiler.com|| ||https://spoiler.com|| <https://discord.com/angled-brackets>"
        local urls = parse_urls(input)

        for _, url in ipairs(urls) do
            print(url)
        end

        print("Adv")

        input = "Check this out: https://google.comhttps://discord.com and also example.co.uk/path?query=1#fragment plus a fake: discordhttps://real.com https://hello.zip/redirect?url=https://google.com/in-redirect !discord.gg/acnh-world!!!\n\n!discord.gg/infinity\nCheck out my totally fake ftp server at ftp.example.zip/ftp-me-bro ftp.example.zip/smily:) path.https://googgles.com.https://google.com!!! google.com/forlife?forlife=true abc.xyz/redirect?redirect=https://google.com?. ftp://ftpserver.com/abc.https://google.com/meow"
        urls = parse_urls(input)
        for _, url in ipairs(urls) do
            print(url)
        end
    end

    main()

    -- Dependencies and helper functions
    -- Assume that the function parse_urls(text) already exists.
    -- Helper function to deeply compare two arrays for equality.
    local function deep_equal(t1, t2)
        if type(t1) ~= "table" or type(t2) ~= "table" then
            return t1 == t2
        end
        if #t1 ~= #t2 then
            return false
        end
        for i = 1, #t1 do
            if t1[i] ~= t2[i] then
                return false
            end
        end
        return true
    end

    -- Test functions
    function test_simple_urls()
        local text = "Visit http://example.com or https://www.google.com/search?q=test#fragment also ftp://user:pass@ftp.server.net and git://github.com/user/repo.git"
        local expected = {
            "http://example.com",
            "https://www.google.com/search?q=test#fragment",
            "ftp://user:pass@ftp.server.net",
            "git://github.com/user/repo.git",
        }
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_scheme_less_urls()
        local text = "Check example.com and sub.domain.co.uk. Also test.org/path is okay."
        local expected = {"example.com", "sub.domain.co.uk", "test.org/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_mixed_urls()
        local text = "URL: https://first.example.com/path then some text example.net?query=1 and finally ftp://old.site.org."
        local expected = {"https://first.example.com/path", "example.net?query=1", "ftp://old.site.org"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_no_urls()
        local text = "Just some regular text without any domains or schemes."
        local expected = {}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_invalid_tlds()
        local text = "Invalid domains: short.x or domain.12 or just numbers 123.456.789.0 or bad-tld.c-m"
        local expected = {}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_invalid_labels()
        local text = "No: a.-b.com or start-.com or end.com- or double..dot.com"
        local expected = {}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_context_discord_https()
        local text = "Join discordhttps://real.com now!"
        local expected = {"https://real.com"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_context_path_https()
        local text = "See path.https://google.com/maps"
        local expected = {"https://google.com/maps"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_context_prefix_dot_schemeless()
        local text = "Check word.example.com for info."
        local expected = {"word.example.com"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_edge_cases()
        local text = "Ends with url: example.com. Punctuation(https://test.net). Bracket[ftp://bracket.org/]. Final one: last.io"
        local expected = {"example.com", "https://test.net", "ftp://bracket.org/", "last.io"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_utf8_text()
        local text_mixed = "Text before http://ascii.com and after café then other.net."
        local expected_mixed = {"http://ascii.com", "other.net"}
        assert(deep_equal(parse_urls(text_mixed), expected_mixed))
    end

    function test_only_tld_like()
        local text = ".com .net"
        local expected = {}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_single_letter_tld_fail()
        local text = "domain.c"
        local expected = {}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_numeric_tld_fail()
        local text = "domain.12"
        local expected = {}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_complex_path_query()
        local text = "Go to https://example.com:8080/a/b-c_d.e~f?key1=val1&key2=v%20a%26l;e#section-1.part_2"
        local expected = {"https://example.com:8080/a/b-c_d.e~f?key1=val1&key2=v%20a%26l;e#section-1.part_2"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_trailing_dot_exclusion()
        local text = "Check example.com."
        local expected = {"example.com"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_trailing_comma_exclusion()
        local text = "Found at example.com, click it."
        local expected = {"example.com"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_in_parentheses_exclusion()
        local text = "See (https://example.com)"
        local expected = {"https://example.com"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_in_brackets_exclusion()
        local text = "Link: [http://test.org/path]"
        local expected = {"http://test.org/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_empty_string()
        local text = ""
        local expected = {}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_no_partial_parse_on_invalid_label()
        local text = "invalid double..dot.com url"
        local expected = {}
        assert(deep_equal(parse_urls(text), expected))

        local text2 = "invalid start-.com url"
        local expected2 = {}
        assert(deep_equal(parse_urls(text2), expected2))

        local text3 = "invalid end.com- url"
        local expected3 = {}
        assert(deep_equal(parse_urls(text3), expected3))

        local text4 = "a.-b.com"
        local expected4 = {}
        assert(deep_equal(parse_urls(text4), expected4))
    end

    function test_port_number()
        local text = "Connect to site.com:8080 or http://anothersite.net:90/path"
        local expected = {"site.com:8080", "http://anothersite.net:90/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_colon_not_port()
        local text = "Look at site.com:notaport and http://site.net:path"
        local expected = {"site.com", "http://site.net:path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_t()
        local a = parse_urls("(discord.gg/acnh)[discord.gg] is the best")
        assert(deep_equal(a, {"discord.gg/acnh", "discord.gg"}))
    end

    function test_masked_url()
        local text = "Hello [masked url](https://google.com/masked)"
        local expected = {"https://google.com/masked"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_pipe_delimited_url()
        local text = "||google.com||"
        local expected = {"google.com"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_multiple_schemes()
        local text = "Try http://test.com and https://secure.test.com or ftp://files.test.com."
        local expected = {"http://test.com", "https://secure.test.com", "ftp://files.test.com"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_query_and_fragment()
        local text = "Visit https://example.com/path?query=value#fragment."
        local expected = {"https://example.com/path?query=value#fragment"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_special_characters()
        local text = "Check https://example.com/path?q=test&a=b#section-1."
        local expected = {"https://example.com/path?q=test&a=b#section-1"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_underscores()
        local text = "See https://example.com/path_with_underscores."
        local expected = {"https://example.com/path_with_underscores"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_hyphens()
        local text = "Visit https://example.com/path-with-hyphens."
        local expected = {"https://example.com/path-with-hyphens"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_subdomain()
        local text = "Go to https://sub.example.com."
        local expected = {"https://sub.example.com"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_port()
        local text = "Connect to https://example.com:8080."
        local expected = {"https://example.com:8080"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_auth()
        local text = "Access ftp://user:pass@example.com."
        local expected = {"ftp://user:pass@example.com"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_ipv4()
        local text = "Ping http://192.168.1.1."
        local expected = {"http://192.168.1.1"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_slash()
        local text = "Go to https://example.com/."
        local expected = {"https://example.com/"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_question_mark()
        local text = "See https://example.com/path?"
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_hash()
        local text = "Check https://example.com/path#."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_exclamation()
        local text = "Visit https://example.com/path!"
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_percent()
        local text = "Go to https://example.com/path%."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_ampersand()
        local text = "See https://example.com/path&."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_equals()
        local text = "Check https://example.com/path=."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_plus()
        local text = "Visit https://example.com/path+."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_asterisk()
        local text = "Go to https://example.com/path*."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_at()
        local text = "See https://example.com/path@."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_dollar()
        local text = "Check https://example.com/path$."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_caret()
        local text = "Visit https://example.com/path^."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_backtick()
        local text = "Go to https://example.com/path`."
        local expected = {"https://example.com/path"}
        assert(deep_equal(parse_urls(text), expected))
    end

    function test_url_with_trailing_tilde()
        local text = "See https://example.com/path~."
        local expected = {"https://example.com/path~"}
        assert(deep_equal(parse_urls(text), expected))
    end

    -- Run all tests
    local function run_tests()
        local time = os.clock()
        test_simple_urls()
        test_scheme_less_urls()
        test_mixed_urls()
        test_no_urls()
        test_invalid_tlds()
        test_invalid_labels()
        test_context_discord_https()
        test_context_path_https()
        test_context_prefix_dot_schemeless()
        test_edge_cases()
        test_utf8_text()
        test_only_tld_like()
        test_single_letter_tld_fail()
        test_numeric_tld_fail()
        test_complex_path_query()
        test_trailing_dot_exclusion()
        test_trailing_comma_exclusion()
        test_url_in_parentheses_exclusion()
        test_url_in_brackets_exclusion()
        test_empty_string()
        test_no_partial_parse_on_invalid_label()
        test_port_number()
        test_colon_not_port()
        test_t()
        test_masked_url()
        test_pipe_delimited_url()
        test_multiple_schemes()
        test_url_with_query_and_fragment()
        test_url_with_special_characters()
        test_url_with_underscores()
        test_url_with_hyphens()
        test_url_with_subdomain()
        test_url_with_port()
        test_url_with_auth()
        test_url_with_ipv4()
        test_url_with_trailing_slash()
        test_url_with_trailing_question_mark()
        test_url_with_trailing_hash()
        test_url_with_trailing_exclamation()
        test_url_with_trailing_percent()
        test_url_with_trailing_ampersand()
        test_url_with_trailing_equals()
        test_url_with_trailing_plus()
        test_url_with_trailing_asterisk()
        test_url_with_trailing_at()
        test_url_with_trailing_dollar()
        test_url_with_trailing_caret()
        test_url_with_trailing_backtick()
        test_url_with_trailing_tilde()
        local elapsed = os.clock() - time
        print(`All tests passed in {elapsed * 1000} ms!`)
    end

    -- Execute tests
    run_tests()
end

--[[
Was originally converted from Rust code:

fn parse_urls(input: &str) -> Vec<String> {
    let protocols = ["https://", "http://", "ftp://", "git://"];
    let mut urls = Vec::new();
    let mut i = 0;

    while i < input.len() {
        let mut next_protocol = None;
        for &protocol in &protocols {
            if let Some(pos) = input[i..].find(protocol) {
                let abs_pos = i + pos;
                if next_protocol.map_or(true, |(p, _)| abs_pos < p) {
                    next_protocol = Some((abs_pos, protocol));
                }
            }
        }

        if let Some((p, protocol)) = next_protocol {
            let segment = &input[i..p];
            urls.extend(extract_scheme_less_urls(segment));

            let start = p + protocol.len();
            let remaining = &input[start..];
            let end = remaining
                .find(|c: char| c.is_whitespace() || c == ')' || c == '!' || c == ']' || c == '(')
                .unwrap_or(remaining.len());

            let mut url = input[p..start + end].to_string();

            // Check for embedded protocol and split smartly
            let mut split_found = false;
            for &proto in &protocols {
                if let Some(inner_pos) = url[protocol.len()..].find(proto) {
                    let split_at = protocol.len() + inner_pos;
                    let preceding_char = url.as_bytes().get(split_at.wrapping_sub(1)).copied().unwrap_or(b' ');

                    if preceding_char == b'.' || preceding_char.is_ascii_whitespace() || preceding_char.is_ascii_punctuation() {
                        let first = url[..split_at - 1].trim_end_matches(|c: char| c.is_ascii_punctuation() && c != '/').to_string();
                        let second = url[split_at..].trim_end_matches(|c: char| c.is_ascii_punctuation() && c != '/').to_string();
                        println!("first: {}, second: {}", first, second);
                        urls.push(first);
                        urls.push(second);
                        i = p + split_at;
                        split_found = true;
                        break;
                    }
                }
            }

            if !split_found {
                // Ensure IPv6 addresses are correctly handled
                if url.starts_with("http://[") && !url.ends_with(']') {
                    if let Some(closing_bracket_pos) = remaining[..end].find(']') {
                        url = input[p..start + closing_bracket_pos + 1].to_string();
                    }
                }
                urls.push(url.trim_end_matches(|c: char| c == '.' || c == ',' || c == '!' || c == ':' || c == ';' || c == '&' || c == '*' || c == '@' || c == '^' || c == '`' || c == '$' || c == '=' || c == '#' || c == '%' || c == '+' || c == '?' || c == '|' || c == '<' || c == '>').to_string());
                i = start + end;
            }
        } else {
            let segment = &input[i..];
            urls.extend(extract_scheme_less_urls(segment));
            break;
        }
    }

    urls
}

fn is_valid_label(label: &str) -> bool {
    !label.is_empty() &&
    !label.starts_with('-') &&
    !label.ends_with('-') &&
    label.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

fn is_valid_tld(tld: &str) -> bool {
    tld.len() > 1 && tld.chars().all(|c| c.is_ascii_alphabetic())
}

fn find_valid_domain(s: &str) -> Option<&str> {
    let mut labels = Vec::new();
    let mut start = 0;
    for (i, c) in s.char_indices() {
        if c == '.' {
            if start == i {
                // Leading dot or consecutive dots
                return None;
            }
            let label = &s[start..i];
            if !is_valid_label(label) {
                return None;
            }
            labels.push(label);
            start = i + 1;
        } else if !c.is_ascii_alphanumeric() && c != '-' {
            // Stop at port, path, or invalid character
            break;
        }
    }
    // Handle the last label
    if start < s.len() {
        let last_label = &s[start..];
        if is_valid_label(last_label) {
            labels.push(last_label);
        } else {
            // Last label is invalid; check accumulated labels
        }
    }
    if labels.len() >= 2 && is_valid_tld(labels.last().unwrap()) {
        Some(&s[0..s.len()])
    } else {
        None
    }
}

fn extract_scheme_less_urls(segment: &str) -> Vec<String> {
    let mut urls = Vec::new();
    let mut i = 0;

    while i < segment.len() {
        let potential_end = segment[i..]
            .find(|c: char| {
                !(c.is_alphanumeric() || c == '.' || c == '-' || c == ':' || c == '/' || c == '?' || c == '&' || c == '=' || c == '#' || c == '%')
            })
            .unwrap_or(segment.len() - i);
        let potential_url = &segment[i..i + potential_end].trim_start_matches(|c: char| !c.is_alphanumeric());

        if !potential_url.is_empty() {
            if let Some(domain) = find_domain(potential_url) {
                let domain_end = domain.len();
                let mut url_to_push = if domain_end < potential_url.len() {
                    let next_char = potential_url[domain_end..].chars().next().unwrap_or('\0');
                    if next_char == '/' || next_char == '?' || next_char == '#' || next_char == '=' {
                        potential_url
                    } else {
                        &potential_url[..domain_end]
                    }
                } else {
                    domain
                };

                let mut url_len = url_to_push.len();

                // Check for query-embedded urls (e.g., url=https://target.com)
                if url_to_push.contains('?') || url_to_push.contains('=') {
                    if let Some(extra) = extract_query_embedded_url(&segment[i + url_len..]) {
                        url_len += extra.len();
                        url_to_push = &segment[i..i + url_len];
                    }
                }

                let cleaned_url = url_to_push.trim_end_matches(|c: char| c == '.' || c == ',' || c == '!' || c == ':' || c == ';' || c == '&' || c == '*' || c == '@' || c == '^' || c == '`' || c == '$' || c == '=' || c == '#' || c == '%' || c == '+' || c == '?' || c == '<' || c == '|' || c == '>');
                urls.push(cleaned_url.to_string());
                i += url_len;
            } else {
                i += potential_end.max(1);
            }
        } else {
            i += 1;
        }
    }
    urls
}


fn extract_query_embedded_url(segment: &str) -> Option<&str> {
    let protocols = ["https://", "http://", "ftp://", "git://"];
    let mut max_end = 0;

    for proto in protocols {
        if let Some(pos) = segment.find(proto) {
            let rest = &segment[pos..];
            let url_end = rest.find(|c: char| c.is_whitespace() || c == ')' || c == '!' || c == ']' || c == '(')
                .unwrap_or(rest.len());
            max_end = pos + url_end;
            break;
        }
    }

    if max_end > 0 {
        Some(&segment[..max_end])
    } else {
        None
    }
}

fn find_domain(s: &str) -> Option<&str> {
    let path_start = s.find(|c: char| c == '/' || c == '?' || c == '#').unwrap_or(s.len());
    let domain_port = &s[..path_start];

    if let Some(colon_pos) = domain_port.find(':') {
        let domain_part = &domain_port[..colon_pos];
        let port_part = &domain_port[colon_pos + 1..];
        if let Some(domain) = find_valid_domain(domain_part) {
            if port_part.chars().all(|c| c.is_ascii_digit()) && !port_part.is_empty() {
                // Valid port: include domain and port
                Some(&s[..path_start])
            } else {
                // Invalid port: return just the domain
                Some(domain)
            }
        } else {
            None
        }
    } else {
        find_valid_domain(domain_port).map(|_| &s[..path_start])
    }
}

fn main() {
    let input = "discordhttps://real.com random text https://discord.gg/8PmaCxnS ftp://some-server.example-site.org more http://192.168.1.1 text sub.domain.co.uk and path.https://google.com git://netsocialoss discord.gg/acnh is the best.https://google.com/best ||spoiler.com|| ||https://spoiler.com|| <https://discord.com/angled-brackets>";
    let urls = parse_urls(&input);

    for url in urls {
        println!("{}", url);
    }

    println!("Adv");

    let input = "Check this out: https://google.comhttps://discord.com and also example.co.uk/path?query=1#fragment plus a fake: discordhttps://real.com https://hello.zip/redirect?url=https://google.com/in-redirect !discord.gg/acnh-world!!!\n\n!discord.gg/infinity\nCheck out my totally fake ftp server at ftp.example.zip/ftp-me-bro ftp.example.zip/smily:) path.https://googgles.com.https://google.com!!! google.com/forlife?forlife=true abc.xyz/redirect?redirect=https://google.com?. ftp://ftpserver.com/abc.https://google.com/meow";

    let urls = parse_urls(&input);
    for url in urls {
        println!("{}", url);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_urls() {
        let text = "Visit http://example.com or https://www.google.com/search?q=test#fragment also ftp://user:pass@ftp.server.net and git://github.com/user/repo.git";
        let expected = vec![
            "http://example.com",
            "https://www.google.com/search?q=test#fragment",
            "ftp://user:pass@ftp.server.net",
            "git://github.com/user/repo.git",
        ];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_scheme_less_urls() {
        let text = "Check example.com and sub.domain.co.uk. Also test.org/path is okay.";
        let expected = vec!["example.com", "sub.domain.co.uk", "test.org/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_mixed_urls() {
        let text = "URL: https://first.example.com/path then some text example.net?query=1 and finally ftp://old.site.org.";
        let expected = vec!["https://first.example.com/path", "example.net?query=1", "ftp://old.site.org"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_no_urls() {
        let text = "Just some regular text without any domains or schemes.";
        let expected: Vec<&str> = vec![];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_invalid_tlds() {
        let text = "Invalid domains: short.x or domain.12 or just numbers 123.456.789.0 or bad-tld.c-m";
        let expected: Vec<&str> = vec![];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_invalid_labels() {
        let text = "No: a.-b.com or start-.com or end.com- or double..dot.com";
        let expected: Vec<&str> = vec![];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_context_discord_https() {
        let text = "Join discordhttps://real.com now!";
        let expected = vec!["https://real.com"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_context_path_https() {
        let text = "See path.https://google.com/maps";
        let expected = vec!["https://google.com/maps"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_context_prefix_dot_schemeless() {
        let text = "Check word.example.com for info.";
        let expected = vec!["word.example.com"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_edge_cases() {
        let text = "Ends with url: example.com. Punctuation(https://test.net). Bracket[ftp://bracket.org/]. Final one: last.io";
        let expected = vec!["example.com", "https://test.net", "ftp://bracket.org/", "last.io"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_utf8_text() {
        let text_mixed = "Text before http://ascii.com and after café then other.net.";
        let expected_mixed = vec!["http://ascii.com", "other.net"];
        assert_eq!(parse_urls(text_mixed), expected_mixed);
    }

    #[test]
    fn test_only_tld_like() {
        let text = ".com .net";
        let expected: Vec<&str> = vec![];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_single_letter_tld_fail() {
        let text = "domain.c";
        let expected: Vec<&str> = vec![];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_numeric_tld_fail() {
        let text = "domain.12";
        let expected: Vec<&str> = vec![];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_complex_path_query() {
        let text = "Go to https://example.com:8080/a/b-c_d.e~f?key1=val1&key2=v%20a%26l;e#section-1.part_2";
        let expected = vec!["https://example.com:8080/a/b-c_d.e~f?key1=val1&key2=v%20a%26l;e#section-1.part_2"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_trailing_dot_exclusion() {
        let text = "Check example.com.";
        let expected = vec!["example.com"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_trailing_comma_exclusion() {
        let text = "Found at example.com, click it.";
        let expected = vec!["example.com"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_in_parentheses_exclusion() {
        let text = "See (https://example.com)";
        let expected = vec!["https://example.com"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_in_brackets_exclusion() {
        let text = "Link: [http://test.org/path]";
        let expected = vec!["http://test.org/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_empty_string() {
        let text = "";
        let expected: Vec<&str> = vec![];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_no_partial_parse_on_invalid_label() {
        let text = "invalid double..dot.com url";
        let expected: Vec<&str> = vec![];
        assert_eq!(parse_urls(text), expected);

        let text2 = "invalid start-.com url";
        let expected2: Vec<&str> = vec![];
        assert_eq!(parse_urls(text2), expected2);

        let text3 = "invalid end.com- url";
        let expected3: Vec<&str> = vec![];
        assert_eq!(parse_urls(text3), expected3);

        let text4 = "a.-b.com";
        let expected4: Vec<&str> = vec![];
        assert_eq!(parse_urls(text4), expected4);
    }

    #[test]
    fn test_port_number() {
        let text = "Connect to site.com:8080 or http://anothersite.net:90/path";
        let expected = vec!["site.com:8080", "http://anothersite.net:90/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_colon_not_port() {
        let text = "Look at site.com:notaport and http://site.net:path";
        let expected = vec!["site.com", "http://site.net:path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_t() {
        let a = parse_urls("(discord.gg/acnh)[discord.gg] is the best");
        assert_eq!(a, vec!["discord.gg/acnh", "discord.gg"]);
    }

    #[test]
   fn test_masked_url() {
    let text = "Hello [masked url](https://google.com/masked)";
    let expected = vec!["https://google.com/masked"];
    assert_eq!(parse_urls(text), expected);
  }

  #[test]
fn test_pipe_delimited_url() {
    let text = "||google.com||";
    let expected = vec!["google.com"];
    assert_eq!(parse_urls(text), expected);
}
    #[test]
    fn test_multiple_schemes() {
        let text = "Try http://test.com and https://secure.test.com or ftp://files.test.com.";
        let expected = vec![
            "http://test.com",
            "https://secure.test.com",
            "ftp://files.test.com",
        ];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_query_and_fragment() {
        let text = "Visit https://example.com/path?query=value#fragment.";
        let expected = vec!["https://example.com/path?query=value#fragment"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_special_characters() {
        let text = "Check https://example.com/path?q=test&a=b#section-1.";
        let expected = vec!["https://example.com/path?q=test&a=b#section-1"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_underscores() {
        let text = "See https://example.com/path_with_underscores.";
        let expected = vec!["https://example.com/path_with_underscores"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_hyphens() {
        let text = "Visit https://example.com/path-with-hyphens.";
        let expected = vec!["https://example.com/path-with-hyphens"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_subdomain() {
        let text = "Go to https://sub.example.com.";
        let expected = vec!["https://sub.example.com"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_port() {
        let text = "Connect to https://example.com:8080.";
        let expected = vec!["https://example.com:8080"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_auth() {
        let text = "Access ftp://user:pass@example.com.";
        let expected = vec!["ftp://user:pass@example.com"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_ipv4() {
        let text = "Ping http://192.168.1.1.";
        let expected = vec!["http://192.168.1.1"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_slash() {
        let text = "Go to https://example.com/.";
        let expected = vec!["https://example.com/"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_question_mark() {
        let text = "See https://example.com/path?";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_hash() {
        let text = "Check https://example.com/path#.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_exclamation() {
        let text = "Visit https://example.com/path!";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_percent() {
        let text = "Go to https://example.com/path%.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_ampersand() {
        let text = "See https://example.com/path&.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_equals() {
        let text = "Check https://example.com/path=.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_plus() {
        let text = "Visit https://example.com/path+.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_asterisk() {
        let text = "Go to https://example.com/path*.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_at() {
        let text = "See https://example.com/path@.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_dollar() {
        let text = "Check https://example.com/path$.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_caret() {
        let text = "Visit https://example.com/path^.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_backtick() {
        let text = "Go to https://example.com/path`.";
        let expected = vec!["https://example.com/path"];
        assert_eq!(parse_urls(text), expected);
    }

    #[test]
    fn test_url_with_trailing_tilde() {
        let text = "See https://example.com/path~.";
        let expected = vec!["https://example.com/path~"];
        assert_eq!(parse_urls(text), expected);
    }
}
]]

return {
    parseUrls = parse_urls
}