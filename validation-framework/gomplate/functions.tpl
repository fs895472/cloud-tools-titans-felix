{{- define "process_routing_validation" -}}
  {{- $routing := .routing -}}
  {{- $clusters := .clusters -}}
  {{- $cluster := .cluster -}}
  {{- $respfile := .respfile -}}
  {{- $direction := .direction -}}
  {{- $reportfile := .reportfile -}}
  {{- if $routing -}}
    {{- $scheme := .scheme -}}
    {{- $rtest := false -}}
    {{- if eq $direction "ingress" -}}
      {{- if hasKey $routing "route" -}}
        {{- $rtest = true -}}
      {{- end -}}
    {{- else if eq $direction "egress" -}}
      {{- $rtest = true -}}
    {{- end -}}
    {{- if $rtest -}}
      {{- if $routing.match -}}
        {{- template "validate_routing_curl_jq_cmds" (dict "routing" $routing "cluster" $cluster "clusters" $clusters "scheme" $scheme "respfile" $respfile "reportfile" $reportfile) -}}
      {{- else if $routing.route -}}
        {{- $route := $routing.route -}}
        {{- if and $route.cluster $clusters -}}
          {{- $clusteValue := index $clusters $route.cluster -}}
          {{- if $clusteValue }}
            {{- range $clusteValue.routes }}
              {{- template "validate_routing_curl_jq_cmds" (dict "routing" . "cluster" $cluster "clusters" $clusters "scheme" $scheme "respfile" $respfile "reportfile" $reportfile) -}}
            {{- end }}
          {{- end }}
        {{- end }}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- define "prepare_jq_path_without_backslash" -}}
  {{- $path = . }}
  {{- $parts := split "." $path }}
  {{- $jpath := "" }}
  {{- range $parts }}
    {{- if ne . "" }}
      {{- if hasSuffix "[]" . }}
        {{- $jpath = printf "%s.%s" $jpath (printf "%s[]" (trimSuffix "[]" | quote)) }}
      {{- else }}
        {{- $jpath = printf "%s.%s" $jpath (printf "%s" . | quote) }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- $jpath -}}
{{- end }}

{{- define "prepare_jq_path" -}}
  {{- $path = . }}
  {{- $parts := split "." $path }}
  {{- $jpath := "" }}
  {{- range $parts }}
    {{- if ne . "" }}
      {{- $jpath = printf "%s.%s" $jpath (printf "\\\"%s\\\"" .) }}
    {{- end }}
  {{- end }}
  {{- $jpath -}}
{{- end }}

{{/* # - path: ".request.domains[].status"
#   select: .=="domain1" 
#   op: eq # eq, ne, prefix, suffix, co, pr, npr
#   value: "active"
#   ### jq -r '.request.domains[] | select(.=="domain1") | .status'
# - path: ".request.domains[].partition_id"
#   select: 
      key: environment
      value: production 
#   op: eq # eq, ne, prefix, suffix, co, pr, npr
#   value: "SEPC"
#   ### jq -r '.request.domains[] | select(.environment=="production") | .partition_id' */}}
{{/* 
          - path: ".keys[].kty"
            select:
              key: .kid
              value: o04CWEnlSJmxa30pukX2oA
            op: eq
            value: RSA */}}

{{- define "build_execute_jq_cmd" -}}
  {{- $path := .path }}
  {{- $resp := ternary "$respheaders" "$resp" (hasKey . "from") }}
  {{- $select := .select }}
  {{- $op := .op | default "eq" }}
  {{- $value := .value | default "" }}
  {{- if $select }}
    {{- $skey := $select.key | default "" }}
    {{- $svalue := $select.value | default "" }}
    {{- if or (eq $skey "") (eq $svalue "")}}
      {{- printf "Unsupported usage: Both key and value are require when using select command %v for path=%s\n >>/tests/logs/error.log\n" $select $path }}
    {{- else }}
      {{- $itms := split "[]" $path }}
       {{- $jpath := "" }}
       {{- $parts := split "." $itms._0 }}
      {{- range $parts }}
        {{- if ne . "" }}
          {{- $jpath = printf "%s.%s" $jpath (printf "%s" . | quote) }}
        {{- end }}
      {{- end }}
     {{- $parts := split "." $skey }}
     {{- $kpath := "" }}
      {{- range $parts}}
        {{- if ne . "" }}
          {{- $kpath = printf "%s.%s" $kpath (printf "%s" . | quote) }}
        {{- end }}
      {{- end }}
      {{- $parts = split "." $itms._1 }}
      {{- $jobj := "" }}
      {{- range $parts }}
        {{- if ne . "" }}
          {{- $jobj = printf "%s.%s" $jobj (printf "%s" . | quote) }}
        {{- end }}
      {{- end }}
      {{- printf "lookupresult=$(echo %s | jq -r '%s[] | select(%s==%s) | %s')\n" $resp $jpath $kpath ($svalue | quote) $jobj }}    
    {{- end }}
  {{- else }}
    {{- if hasSuffix "[]" $path }}
      {{- if and (eq $op "has") (ne $value "") }}
        {{- $parts := split "." $path }}
        {{- $jpath := "" }}
        {{- range $parts }}
          {{- if ne . "" }}
            {{- if hasSuffix "[]" . }}
              {{- $jpath = printf "%s.%s" $jpath (printf "%s[]" (trimSuffix "[]" | quote)) }}
            {{- else }}
              {{- $jpath = printf "%s.%s" $jpath (printf "%s" . | quote) }}
            {{- end }}
          {{- end }}
        {{- end }}
        {{- printf "lookupresult=$(echo %s | jq -r '%s | select(.==%s) | .')\n"  $resp $jpath ($value | quote)}}
      {{- else }}
        {{- printf "Unsupported usage: only \"has\" oprator(%s) is supported on the path(%s)[] with value(%s)\n >>/tests/logs/error.log\n" $op $path $value }}
      {{- end }}
    {{- else }}
      {{- $parts := split "." $path }}
      {{- $jpath := "" }}
      {{- range $parts }}
        {{- if ne . "" }}
          {{- $jpath = printf "%s.%s" $jpath (printf "\\\"%s\\\"" .) }}
        {{- end }}
      {{- end }}   
      {{- printf "lookupresult=$(echo %s | jq -r %s)\n"  $resp  $jpath }}
    {{- end }}
  {{- end }}
{{- end }}


{{- define "validate_routing_curl_jq_cmds" -}}
  {{- $routing := .routing -}}
  {{- $respfile := .respfile -}}
  {{- $reportfile := .reportfile -}}
  {{- $cluster := .cluster -}}
  {{- $scheme := .scheme -}}
  {{- $path := "" -}}
  {{- $cmd := "" -}}
  {{- $method := "GET" -}}
  {{- $headers := dict -}}
  {{- if hasKey $routing "match" -}}
    {{- $supported := true }}
    {{- $tokenCheck := $routing.tokenCheck | default false }}
    {{- $authType := "Bearer" }}
    {{- $rbac := $routing.rbac }}
    {{- $match := $routing.match -}}
    {{- if hasKey $match "method" -}}
      {{- $method = $match.method -}}
    {{- end -}}
    {{- if hasKey $match "prefix" -}}
      {{- $path = printf "%s/abc" (trimSuffix "/" $match.prefix) -}}
    {{- else if hasKey $match "path" -}}
      {{- $path = printf "%s" $match.path -}}
    {{- else if hasKey $match "regex" -}}
      {{/* $path = randomRegex $match.regex */}}
      {{- $supported = false }}
    {{- end -}}
    {{- if $supported }}
      {{- if hasKey $match "headers" -}}
        {{- range $match.headers -}}
          {{- $key := .key -}}
          {{- $val := "" -}}
          {{- if eq $key "Authorization" -}}
            {{- if hasPrefix "Basic" .sw -}}
              {{- $authType = "Basic" }}
              {{/* {{- $val = printf "Basic %s" (b64enc "test:test") -}} */}}
            {{- end -}}
            {{- $tokenCheck = true }}
          {{- else if hasKey . "eq" -}}
            {{- $val = .eq -}}
          {{- else if hasKey . "sw" -}}
            {{- $val = printf "%s%s" .sw (randAscii 5) -}}          
          {{- else if hasKey . "ew" -}}
            {{- $val = printf "%s%s" (randAscii 5) .ew -}}             
          {{- else if hasKey . "co" -}}
            {{- $val = printf "%s%s%s" (randAscii 5) .co (randAscii 5) -}}              
          {{- else if hasKey . "lk" -}}
            {{/*- $val = randomRegex .lk -*/}}
          {{- else if hasKey . "pr" -}}
            {{- if .pr -}}
              {{- $val = "def" -}}          
            {{- end }}
          {{- else if hasKey . "neq" -}}
            {{- $val = printf "%s%s" .neq (randAscii 5) -}}          
          {{- else if hasKey . "nsw" -}}
            {{- $val = printf "%s%s" (randAscii 5) .nsw -}}          
          {{- else if hasKey . "new" -}}
            {{- $val = printf "%s%s" .new (randAscii 5) -}} 
          {{- else if hasKey . "nco" -}}
            {{- $val = printf "%s" (randAscii 5) -}} 
          {{- else if hasKey . "nlk" -}}
          {{/* {{- $val = printf "%s" (randAscii 5) -}}  */}}
          {{- end -}}
          {{- if ne $val "" -}}
            {{- if eq $key ":path" -}}
              {{- $path = $val -}}
            {{- else if eq $key ":method" -}}
              {{- if .eq }}
                {{- $method = upper .eq -}}
              {{- else if .neq -}}
                {{- $neq := upper .neq -}}
                {{- if ne "GET" $neq -}}
                  {{- $method = $neq -}}
                {{- else if ne "POST" $neq -}}
                  {{- $method = $neq -}}
                {{- else if ne "PUT" $neq -}}
                  {{- $method = $neq -}}
                {{- else if ne "DELETE" $neq -}}
                  {{- $method = $neq -}}
                {{- else if ne "PATCH" $neq -}}
                  {{- $method = $neq -}}
                {{- end -}}
              {{- end }}
            {{- else -}}
              {{- $_ := set $headers $key $val -}}
            {{- end -}}
          {{- end -}}
        {{- end }}
      {{- end }}
      {{- $hdrStr := "" }}
      {{- range $k, $v := $headers -}}
          {{- if eq  $hdrStr "" -}}
            {{- $hdrStr = printf "-H %s:%s" $k $v -}}
          {{- else -}}
            {{- $hdrStr = printf "%s %s:%s" $hdrStr $k $v -}}
          {{- end -}}
      {{- end -}}
      {{- if $rbac }}
        {{- $policies := $rbac.policies }}
        {{- range $policies }}
          {{- $name := .name }}
          {{- $privs := "" }}
          {{- $scope := "" }}            
          {{- $roles := "" }}            
          {{- $cid := "" }}
          {{- $did := "" }}
          {{- $uri := "" }}
          {{- $clid := "" }}
          {{- $rules := .rules }}          
          {{- $requestToken := false }}
          {{- range $rules }}
            {{- if hasPrefix "request.token" .lop }}            
              {{- $claim := trimPrefix "request.token[" .lop | trimSuffix "]" }}
              {{- if eq $claim "scope" }}
                {{- if eq .op "co" }}
                  {{- $scope = .val }}
                  {{- $requestToken = true }}
                {{- end }}
              {{- else if eq $claim "privs" }}
                {{- if eq .op "co" }}
                  {{- $privs = ternary .val (printf "%s %s" $privs .val) (eq $privs "") }}
                  {{- $requestToken = true }}
                {{- end }}
              {{- else if eq $claim "roles" }}
                {{- if eq .op "co" }}
                  {{- $roles = ternary .val (printf "%s %s" $roles .val) (eq $roles "") }}
                  {{- $requestToken = true }}
                {{- end }}
              {{- else if eq $claim "customer_id" }}
                {{- if eq .op "eq" }}
                  {{- $cid = .val }}
                  {{- $requestToken = true }}
                {{- else if eq .op "ne" }}
                  {{- $cid = randAlpha 8 }}
                  {{- $requestToken = true }}
                {{- end }}
              {{- else if eq $claim "domain_id" }}
                {{- if eq .op "eq" }}
                  {{- $did = .val }}
                  {{- $requestToken = true }}
                {{- else if eq .op "ne" }}
                  {{- $did = randAlpha 8 }}
                  {{- $requestToken = true }}
                {{- end }}
              {{- else if eq $claim "uri" }}
                {{- if eq .op "eq" }}
                  {{- $uri = .val }}
                  {{- $requestToken = true }}
                {{- else if eq .op "prefix" }}
                  {{- $uri = printf "%s%s" .val (randAlpha 3) }}
                  {{- $requestToken = true }}
                {{- end }}
              {{- else if eq $claim "client_id" }}
                {{- if eq .op "eq" }}
                  {{- $did = .val }}
                  {{- $requestToken = true }}
                {{- else if eq .op "ne" }}
                  {{- $requestToken = true }}
                {{- end }}
              {{- end }}
            {{- end }}
          {{- end }}
          {{- if $requestToken }}
            {{- printf "get_token %s %s %s %s %s %s %s\n" ($privs | quote) ($scope | quote) ($roles | quote) ($cid | quote) ($did | quote) ($uri | quote) ($clid | quote) }}
            {{- printf "http_call %s %s %s %s\n" ($method | quote) (printf "%s%s" $scheme $path | quote) (printf "%s" $hdrStr | squote) (printf "%s" "Bearer" | quote) -}}
            {{/* {{- printf "unset validation_array && declare -A validation_array\n" }}
            {{- printf "validation_array[%s]=%s\n" (printf "%s" "code" | quote) (printf "eq:::200" | quote) }}
            {{- printf "check_and_report\n" }} */}}
            {{- printf "check_test_call\n" -}}
            {{- printf "echo %s >> %s\n" (printf "Test case[auto][rbac:positive] result[$test_result]: call %s %s%s" $method $scheme $path | quote) $reportfile }}
          {{- end }}
        {{- end }}
      {{- else }}
        {{- printf "http_call %s %s %s\n" ($method | quote) (printf "%s%s" $scheme $path | quote) (printf "%s" $hdrStr | squote) -}}
      {{- end }}
      {{- if hasKey $routing "redirect" -}}
        {{- $redirect := $routing.redirect -}}
        {{/* {{- printf "unset validation_array && declare -A validation_array\n" }}
        {{- printf "validation_array[%s]=%s\n" (printf "%s" "code" | quote) (printf "eq:::%s" ($redirect.responseCode | default "301") | quote) }}
        {{- printf "check_and_report\n" }} */}}
        {{- printf "check_test_call %s\n" (($redirect.responseCode | default "301") | quote) }}
        {{- printf "echo %s >> %s\n" (printf "Test case[auto][redirect] result[$test_result]: call %s %s%s" $method $scheme $path | quote) $reportfile }}
      {{- else if hasKey $routing "directResponse" -}}
        {{- $directResponse := $routing.directResponse -}}
        {{/* {{- printf "unset validation_array && declare -A validation_array\n" }}
        {{- printf "validation_array[%s]=%s\n" (printf "%s" "code" | quote) (printf "eq:::%s" $directResponse.status | quote) }}
        {{- printf "check_and_report\n" }} */}}
        {{- printf "check_test_call %s\n" ($directResponse.status | quote) }}
        {{- printf "echo %s >> %s\n" (printf "Test case[auto][directResponse] result[$test_result]: call %s %s%s" $method $scheme $path | quote) $reportfile }}
      {{- else if hasKey $routing "route" -}}
        {{- $route := $routing.route -}}
        {{/* {{- printf "unset validation_array && declare -A validation_array\n" }}
        {{- printf "validation_array[%s]=%s\n" (printf "%s" "code" | quote) (printf "eq:::%s" "200" | quote) }} */}}
        {{- printf "check_test_call\n" }}
        {{- if hasKey $route "prefixRewrite" -}}
          {{/* {{- printf "validation_array[%s]=%s\n" (printf "%s" ".http.originalUrl" | quote) (printf "prefix:::%s" $route.prefixRewrite | quote) }} */}}
          {{- template "build_execute_jq_cmd" (dict "path" ".http.originalUrl") }}
          {{- printf "test_check %s %s\n" ($route.prefixRewrite | quote) ("prefix" | quote) }}
        {{- end -}}
        {{/* {{- printf "validation_array[%s]=%s\n" (printf "%s" ".host.hostname" | quote) (printf "eq:::%s" $cluster | quote) }}
        {{- printf "check_and_report\n" }} */}}
          {{- template "build_execute_jq_cmd" (dict "path" ".host.hostname") }}
          {{- printf "test_check %s\n" ($cluster | quote) }}
        {{- printf "echo %s >> %s\n" (printf "Test case[auto][routing - path rewrite]result[$test_result]: call %s %s%s" $method $scheme $path | quote) $reportfile }}
      {{- else -}}
        {{/* {{- printf "unset validation_array && declare -A validation_array\n" }}
        {{- printf "validation_array[%s]=%s\n" (printf "%s" "code" | quote) (printf "eq:::%s" "200" | quote) }}
        {{- printf "check_and_report\n" }} */}}
        {{- printf "check_test_call\n" }}
        {{- printf "echo %s >> %s\n" (printf "Test case[routing] result[$test_result]: call %s %s%s" $method $scheme $path | quote) $reportfile }}
      {{- end -}}
    {{- end }}
  {{- end -}}
{{- end -}}
