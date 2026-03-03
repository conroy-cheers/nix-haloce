merge_registry_json() {
  local name="$1"
  jq -s '
    .[0] as $base
    | .[1] as $overlay
    | $base * $overlay
    | .arch = $base.arch
    | .version = $base.version
    | .location = $base.location
  ' \
    "@WOW64_BASE_ENV@/basePackage/$name.json" \
    "$src/$name.json" \
    > "./base/$name.json"

  json2reg "./base/$name.json" "./base/$name.reg"
}

merge_registry_json system
merge_registry_json user
merge_registry_json userdef
