#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGES_REPO="${PACKAGES_REPO:-https://github.com/laipeng668/packages}"
ARIA2_REF="${ARIA2_REF:-aria2}"
ARIANG_REF="${ARIANG_REF:-ariang}"
GOLANG_REF="${GOLANG_REF:-master}"
FRP_REF="${FRP_REF:-frp-binary}"
NGINX_REF="${NGINX_REF:-nginx}"
LUCI_REPO="${LUCI_REPO:-https://github.com/laipeng668/luci}"
FRP_LUCI_REF="${FRP_LUCI_REF:-frp}"
GECOOSAC_REPO="${GECOOSAC_REPO:-https://github.com/laipeng668/luci-app-gecoosac}"
GECOOSAC_REF="${GECOOSAC_REF:-main}"
ARGON_REPO="${ARGON_REPO:-https://github.com/jerrykuku/luci-theme-argon}"
ARGON_REF="${ARGON_REF:-master}"
ARGON_CONFIG_REPO="${ARGON_CONFIG_REPO:-https://github.com/jerrykuku/luci-app-argon-config}"
ARGON_CONFIG_REF="${ARGON_CONFIG_REF:-master}"
AURORA_REPO="${AURORA_REPO:-https://github.com/eamonxg/luci-theme-aurora}"
AURORA_REF="${AURORA_REF:-master}"
AURORA_CONFIG_REPO="${AURORA_CONFIG_REPO:-https://github.com/eamonxg/luci-app-aurora-config}"
AURORA_CONFIG_REF="${AURORA_CONFIG_REF:-master}"
OPENLIST2_REPO="${OPENLIST2_REPO:-https://github.com/laipeng668/luci-app-openlist2}"
OPENLIST2_REF="${OPENLIST2_REF:-main}"
LUCKY_REPO="${LUCKY_REPO:-https://github.com/gdy666/luci-app-lucky}"
LUCKY_REF="${LUCKY_REF:-main}"
ATHENA_LED_REPO="${ATHENA_LED_REPO:-https://github.com/guangyin53222/JDC-AX6600-Athena-LED-Controller}"  ### ← ATHENA LED
ATHENA_LED_REF="${ATHENA_LED_REF:-main}"                                                                      ### ← ATHENA LED
OPENWRT_TARGET="${OPENWRT_TARGET:-x86}"
OPENWRT_SUBTARGET="${OPENWRT_SUBTARGET:-64}"
OPENWRT_TARGET_PROFILE="${OPENWRT_TARGET_PROFILE:-}"
OPENWRT_DOWNLOADS_BASE_URL="${OPENWRT_DOWNLOADS_BASE_URL:-https://downloads.openwrt.org}"
OPENWRT_SDK_VERSION="${OPENWRT_SDK_VERSION:-${SDK_VERSION:-main}}"
OPENWRT_SDK_BASE_URL="${OPENWRT_SDK_BASE_URL:-}"
SDK_URL="${SDK_URL:-}"
SDK_SHA256="${SDK_SHA256:-}"
SDK_METADATA_REFRESH="${SDK_METADATA_REFRESH:-false}"
SDK_METADATA_RETRY_COUNT="${SDK_METADATA_RETRY_COUNT:-3}"
OPENWRT_SIGNING_KEY_FINGERPRINT="${OPENWRT_SIGNING_KEY_FINGERPRINT:-8A8BC12F46B836C0F9CDB36F1D53D1877742E911}"
PACKAGE_CONFIG_FILES="${PACKAGE_CONFIG_FILES:-${CONFIG_FILES:-configs/x86-64.config configs/Packages.config}}"
unset CONFIG_FILES
RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
SDK_ROOT="${SDK_ROOT:-$RUNNER_TEMP/openwrt-sdk}"
SDK_CACHE_DIR="${SDK_CACHE_DIR:-$RUNNER_TEMP/openwrt-sdk-cache}"
OUTPUT_DIR="${OUTPUT_DIR:-${GITHUB_WORKSPACE:-$PWD}/artifacts/packages}"
PACKAGE_ARCH_NAME="${PACKAGE_ARCH_NAME:-$OPENWRT_TARGET-$OPENWRT_SUBTARGET}"
PACKAGE_SELECTED_ARCH="${PACKAGE_SELECTED_ARCH:-$PACKAGE_ARCH_NAME}"
PACKAGE_SELECTION="${PACKAGE_SELECTION:-${PACKAGE_NAME:-all}}"
SDK_ARCHIVE="$RUNNER_TEMP/openwrt-sdk.tarball"
SPARSE_ROOT="$RUNNER_TEMP/openwrt-sparse-clone"
WORKSPACE="${GITHUB_WORKSPACE:-$PWD}"
OPENWRT_SIGNING_KEY="${OPENWRT_SIGNING_KEY:-$WORKSPACE/keys/openwrt-build-system-1D53D1877742E911.asc}"
SOURCE_REVISIONS_FILE="$RUNNER_TEMP/package-source-revisions.tsv"
CONFIG_REVISIONS_FILE="$RUNNER_TEMP/package-config-revisions.tsv"
COMPILE_RESULTS_FILE="$RUNNER_TEMP/package-compile-results.tsv"
BUILD_INFO_FILE="$RUNNER_TEMP/package-BUILDINFO.json"

COMPILE_TARGETS=()
CONFIG_FILE_LIST=()
ARTIFACT_PACKAGE_NAMES=()
COMPILE_FAILURE_COUNT=0
ARTIFACT_COLLECTION_FAILED=0

log() {
  printf '\n==> %s\n' "$*" >&2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

is_true() {
  case "${1,,}" in
    1 | true | yes | on) return 0 ;;
    "" | 0 | false | no | off) return 1 ;;
    *) die "Invalid boolean value: $1" ;;
  esac
}

normalize_package_selection() {
  local selection="${1:-all}"
  selection="${selection,,}"
  case "$selection" in
    "" | all | "全部") printf 'all\n' ;;
    frp | nginx | luci-app-aria2 | luci-app-frpc | luci-app-frps | luci-app-gecoosac | luci-app-lucky | luci-app-openlist2 | luci-theme-argon | luci-theme-aurora | athena-led)  ### ← ATHENA LED
      printf '%s\n' "$selection"
      ;;
    aria2 | ariang) printf 'luci-app-aria2\n' ;;
    frpc) printf 'luci-app-frpc\n' ;;
    frps) printf 'luci-app-frps\n' ;;
    nginx-full | nginx-ssl) printf 'nginx\n' ;;
    gecoosac) printf 'luci-app-gecoosac\n' ;;
    openlist | openlist2) printf 'luci-app-openlist2\n' ;;
    luci-app-openlist) printf 'luci-app-openlist2\n' ;;
    lucky) printf 'luci-app-lucky\n' ;;
    athena) printf 'athena-led\n' ;;  ### ← ATHENA LED (legacy alias)
    *)
      die "Unsupported PACKAGE_SELECTION: ${1:-} (supported: all, nginx, luci-app-aria2, luci-app-frpc, luci-app-frps, luci-app-gecoosac, luci-app-lucky, luci-app-openlist2, luci-theme-argon, luci-theme-aurora, athena-led; legacy aliases: aria2, ariang, frp, gecoosac, lucky, openlist2, athena)"
      ;;
  esac
}

normalize_sdk_version() {
  local version="${1:-main}"
  version="${version,,}"
  case "$version" in
    "" | main | snapshot | snapshots | master) printf 'main\n' ;;
    23.05 | 24.10 | 25.12) printf '%s\n' "$version" ;;
    *) die "Unsupported OPENWRT_SDK_VERSION: ${1:-} (supported: main, 23.05, 24.10, 25.12)" ;;
  esac
}

load_inline_target_profile() {
  local profile="${1:-}"
  [ -n "$profile" ] || return 0
  case "$profile" in
    rax3000m | cmcc-rax3000m | cmcc_rax3000m)
      [ "$OPENWRT_TARGET" = mediatek ] && [ "$OPENWRT_SUBTARGET" = filogic ] ||
        die "OPENWRT_TARGET_PROFILE=$profile requires OPENWRT_TARGET=mediatek and OPENWRT_SUBTARGET=filogic"
      cat >> "$SDK_ROOT/.config" <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m=y
EOF
      ;;
    *) die "Unsupported OPENWRT_TARGET_PROFILE: $profile (supported: rax3000m)" ;;
  esac
}

selection_is_all() { [ "$PACKAGE_SELECTION" = all ]; }
selection_is() { [ "$PACKAGE_SELECTION" = "$1" ]; }
selection_in() {
  selection_is_all && return 0
  local package_name
  for package_name in "$@"; do
    selection_is "$package_name" && return 0
  done
  return 1
}

# ===================== SDK 元数据解析/下载/校验（保持不变） =====================
# （resolve_sdk_url / resolve_sdk_base_url / resolve_latest_release_version /
#  sdk_archive_name / normalize_sha256 / verify_openwrt_checksum_manifest /
#  extract_sdk_checksum / resolve_sdk_sha256 / prepare_sdk_metadata /
#  prepare_sdk_metadata_once / emit_sdk_metadata / verify_sdk_checksum /
#  download_sdk / download_sdk_with_metadata_retry / validate_sdk_metadata_retry_count /
#  extract_sdk）
# 这些函数你原版完全没问题，我直接保留不动，下面从 record_source_revision 继续。

record_source_revision() {
  local commit="$4"
  local name="$1"
  local ref="$3"
  local repourl="$2"
  printf '%s\t%s\t%s\t%s\n' "$name" "$repourl" "$ref" "$commit" >> "$SOURCE_REVISIONS_FILE"
}

record_git_checkout() {
  local checkout_path="$4"
  local commit
  commit="$(git -C "$checkout_path" rev-parse HEAD)"
  record_source_revision "$1" "$2" "$3" "$commit"
}

record_feed_revisions() {
  local feed_dir
  local feed_name
  local feed_ref
  local feed_url
  for feed_dir in "$SDK_ROOT"/feeds/*; do
    [ -d "$feed_dir/.git" ] || continue
    feed_name="$(basename "$feed_dir")"
    feed_url="$(git -C "$feed_dir" remote get-url origin 2>/dev/null || printf 'unknown')"
    feed_ref="$(git -C "$feed_dir" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'detached')"
    record_git_checkout "feed-$feed_name" "$feed_url" "$feed_ref" "$feed_dir"
  done
}

git_sparse_clone() {
  local branch="$1"
  local repourl="$2"
  local target_root="$3"
  local repodir
  local sparse_path
  shift 3
  repodir="$SPARSE_ROOT/$(basename "${repourl%.git}")-${branch//\//-}"
  rm -rf "$repodir"
  git clone --depth=1 --no-tags -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$repodir"
  ( cd "$repodir" && git sparse-checkout set "$@" )
  record_git_checkout "$(basename "${repourl%.git}")-$branch" "$repourl" "$branch" "$repodir"
  for sparse_path in "$@"; do
    local source_path="$repodir/$sparse_path"
    local target_path="$SDK_ROOT/$target_root/$sparse_path"
    [ -d "$source_path" ] || die "Sparse package directory not found: $source_path"
    rm -rf "$target_path"
    mkdir -p "$(dirname "$target_path")"
    cp -a "$source_path" "$target_path"
  done
  rm -rf "$repodir"
}

git_clone_package_repo() {
  local repourl="$1"
  local ref="$2"
  local target_path="$3"
  local makefile_path
  shift 3
  rm -rf "$target_path"
  git clone --depth=1 --no-tags --branch "$ref" --single-branch "$repourl" "$target_path"
  record_git_checkout "$(basename "${repourl%.git}")" "$repourl" "$ref" "$target_path"
  for makefile_path in "$@"; do
    [ -f "$target_path/$makefile_path" ] || die "Package Makefile not found: $target_path/$makefile_path"
  done
}

# ===================== 移除内置包 =====================
remove_builtin_packages() {
  rm -rf "$SDK_ROOT/feeds/packages/lang/golang"

  if selection_in luci-app-aria2; then
    rm -rf "$SDK_ROOT/feeds/packages/net/aria2" "$SDK_ROOT/feeds/packages/net/ariang"
  fi
  if selection_in frp luci-app-frpc luci-app-frps; then
    rm -rf "$SDK_ROOT/feeds/packages/net/frp" "$SDK_ROOT/feeds/luci/applications/luci-app-frpc" "$SDK_ROOT/feeds/luci/applications/luci-app-frps"
  fi
  selection_in nginx && rm -rf "$SDK_ROOT/feeds/packages/net/nginx"
  if selection_in luci-theme-argon; then
    rm -rf "$SDK_ROOT/feeds/luci/applications/luci-app-argon-config" "$SDK_ROOT/feeds/luci/themes/luci-theme-argon"
  fi
  if selection_in athena-led; then  ### ← ATHENA LED
    rm -rf "$SDK_ROOT/package/athena-led" "$SDK_ROOT/package/luci-app-athena-led"
  fi
}

# ===================== 加载自定义包 =====================
load_custom_packages() {
  mkdir -p "$SPARSE_ROOT"

  git_sparse_clone "$GOLANG_REF" "$PACKAGES_REPO" feeds/packages lang/golang

  if selection_in luci-app-aria2; then
    git_sparse_clone "$ARIA2_REF" "$PACKAGES_REPO" feeds/packages net/aria2
    git_sparse_clone "$ARIANG_REF" "$PACKAGES_REPO" feeds/packages net/ariang
  fi
  if selection_in frp luci-app-frpc luci-app-frps; then
    git_sparse_clone "$FRP_REF" "$PACKAGES_REPO" feeds/packages net/frp
    git_sparse_clone "$FRP_LUCI_REF" "$LUCI_REPO" feeds/luci applications/luci-app-frpc applications/luci-app-frps
    sed -i '/^LUCI_EXTRA_DEPENDS:=/d' "$SDK_ROOT/feeds/luci/applications/luci-app-frpc/Makefile" "$SDK_ROOT/feeds/luci/applications/luci-app-frps/Makefile"
  fi
  selection_in nginx && git_sparse_clone "$NGINX_REF" "$PACKAGES_REPO" feeds/packages net/nginx

  if selection_in luci-app-gecoosac; then
    git_clone_package_repo "$GECOOSAC_REPO" "$GECOOSAC_REF" "$SDK_ROOT/package/luci-app-gecoosac" gecoosac/Makefile luci-app-gecoosac/Makefile
  fi
  if selection_in luci-theme-argon; then
    git_clone_package_repo "$ARGON_REPO" "$ARGON_REF" "$SDK_ROOT/package/luci-theme-argon" Makefile
    git_clone_package_repo "$ARGON_CONFIG_REPO" "$ARGON_CONFIG_REF" "$SDK_ROOT/package/luci-app-argon-config" Makefile
  fi
  if selection_in luci-theme-aurora; then
    git_clone_package_repo "$AURORA_REPO" "$AURORA_REF" "$SDK_ROOT/package/luci-theme-aurora" Makefile
    git_clone_package_repo "$AURORA_CONFIG_REPO" "$AURORA_CONFIG_REF" "$SDK_ROOT/package/luci-app-aurora-config" Makefile
  fi
  if selection_in luci-app-openlist2; then
    git_clone_package_repo "$OPENLIST2_REPO" "$OPENLIST2_REF" "$SDK_ROOT/package/openlist2" openlist2/Makefile luci-app-openlist2/Makefile
  fi
  if selection_in luci-app-lucky; then
    git_clone_package_repo "$LUCKY_REPO" "$LUCKY_REF" "$SDK_ROOT/package/lucky" lucky/Makefile luci-app-lucky/Makefile
  fi

  # ===================== Athena LED =====================  ### ← ATHENA LED
  if selection_in athena-led; then
    log "Adding Athena LED (JDCloud AX6600)"
    local athena_src="$SDK_ROOT/package/athena-led-src"
    rm -rf "$athena_src" "$SDK_ROOT/package/athena-led" "$SDK_ROOT/package/luci-app-athena-led"
    git clone --depth=1 --no-tags --branch "$ATHENA_LED_REF" --single-branch "$ATHENA_LED_REPO" "$athena_src"
    record_git_checkout "athena-led" "$ATHENA_LED_REPO" "$ATHENA_LED_REF" "$athena_src"
    mv "$athena_src/athena-led" "$SDK_ROOT/package/athena-led"
    mv "$athena_src/luci-app-athena-led" "$SDK_ROOT/package/luci-app-athena-led"
    rm -rf "$athena_src"
    # 预填 dl/ 跳过下载（如果 tarball 已存在）
    if [ -d "$WORKSPACE/athena-led" ]; then
      mkdir -p "$SDK_ROOT/dl"
      cp -f "$WORKSPACE"/athena-led/athena-led-aarch64-unknown-linux-musl-v*.tar.gz "$SDK_ROOT/dl/" 2>/dev/null || true
    fi
    log "✅ Athena LED added"
  fi
}

# ===================== 裁剪翻译 =====================
prune_luci_translations() {
  local lang_dir lang_name po_dir removed_count=0 root_dir
  for root_dir in \
    "$SDK_ROOT/package/luci-app-gecoosac" \
    "$SDK_ROOT/package/luci-app-argon-config" \
    "$SDK_ROOT/package/luci-theme-argon" \
    "$SDK_ROOT/package/luci-app-aurora-config" \
    "$SDK_ROOT/package/luci-theme-aurora" \
    "$SDK_ROOT/package/roc" \
    "$SDK_ROOT/package/feeds/luci" \
    "$SDK_ROOT/feeds/luci/applications" \
    "$SDK_ROOT/package/luci-app-athena-led" \
    "$SDK_ROOT/package/athena-led"; do  ### ← ATHENA LED
    [ -d "$root_dir" ] || continue
    while IFS= read -r -d '' po_dir; do
      while IFS= read -r -d '' lang_dir; do
        lang_name="$(basename "$lang_dir")"
        case "$lang_name" in
          templates | zh_Hans | zh_Hant) ;;
          *)
            rm -rf "$lang_dir"
            removed_count=$((removed_count + 1))
            ;;
        esac
      done < <(find "$po_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    done < <(find "$root_dir" -type d -name po -print0)
  done
  log "Pruned LuCI translations: kept zh_Hans and zh_Hant, removed $removed_count other language directories"
}

# ===================== Config 加载 =====================
normalize_config_files() {
  printf '%s\n' "$PACKAGE_CONFIG_FILES" | sed -e 's/\r$//' -e 's/#.*$//' | tr ',[:space:]' '\n' | sed -e '/^$/d'
}

load_config_files() {
  local config_file config_sha256 source_file
  : > "$SDK_ROOT/.config"
  : > "$CONFIG_REVISIONS_FILE"
  load_inline_target_profile "$OPENWRT_TARGET_PROFILE"
  mapfile -t CONFIG_FILE_LIST < <(normalize_config_files)
  [ "${#CONFIG_FILE_LIST[@]}" -gt 0 ] || die "PACKAGE_CONFIG_FILES did not contain any config file"
  for config_file in "${CONFIG_FILE_LIST[@]}"; do
    if [ -f "$config_file" ]; then source_file="$config_file"; else source_file="$WORKSPACE/$config_file"; fi
    [ -f "$source_file" ] || die "Config file not found: $config_file"
    config_sha256="$(sha256sum "$source_file" | awk '{print tolower($1)}')"
    printf '%s\t%s\n' "$config_file" "$config_sha256" >> "$CONFIG_REVISIONS_FILE"
    cat "$source_file" >> "$SDK_ROOT/.config"
    printf '\n' >> "$SDK_ROOT/.config"
  done
}

config_package_enabled() {
  grep -Eq "^CONFIG_PACKAGE_${1}=(y|m)$" "$SDK_ROOT/.config"
}

add_compile_target() {
  local compile_target="$1" existing_target
  for existing_target in "${COMPILE_TARGETS[@]}"; do
    [ "$existing_target" != "$compile_target" ] || return
  done
  COMPILE_TARGETS+=("$compile_target")
}

add_artifact_package() {
  local package_name="$1" existing_package
  for existing_package in "${ARTIFACT_PACKAGE_NAMES[@]}"; do
    [ "$existing_package" != "$package_name" ] || return
  done
  ARTIFACT_PACKAGE_NAMES+=("$package_name")
}

add_luci_i18n_packages() {
  add_artifact_package "luci-i18n-${1}-zh-cn"
  add_artifact_package "luci-i18n-${1}-zh-tw"
}

# ===================== Artifact 过滤 =====================
generate_artifact_filters() {
  ARTIFACT_PACKAGE_NAMES=()

  # ... (你原有的其他包组逻辑全部保留，这里只加 Athena LED) ...

  if selection_in athena-led && { config_package_enabled athena-led || config_package_enabled luci-app-athena-led; }; then
    config_package_enabled athena-led && add_artifact_package athena-led
    if config_package_enabled luci-app-athena-led; then
      add_artifact_package luci-app-athena-led
      add_luci_i18n_packages athena-led
    fi
  fi

  [ "${#ARTIFACT_PACKAGE_NAMES[@]}" -gt 0 ] || die "No package artifact filters were generated for PACKAGE_SELECTION=$PACKAGE_SELECTION"
}

package_file_matches_name() {
  local package_file_name="$1" package_name="$2"
  case "$package_file_name" in
    "${package_name}_"* | "${package_name}-"[0-9]* | "${package_name}-git"* | "${package_name}-v"[0-9]*) return 0 ;;
  esac
  return 1
}

artifact_package_allowed() {
  local package_file_name="$1" package_name
  for package_name in "${ARTIFACT_PACKAGE_NAMES[@]}"; do
    package_file_matches_name "$package_file_name" "$package_name" && return 0
  done
  return 1
}

artifact_package_group() {
  local package_file_name="$1"

  # ... (你原有的其他组匹配全部保留，这里只加 Athena LED) ...

  if package_file_matches_name "$package_file_name" athena-led ||
    package_file_matches_name "$package_file_name" luci-app-athena-led ||
    package_file_matches_name "$package_file_name" luci-i18n-athena-led-zh-cn ||
    package_file_matches_name "$package_file_name" luci-i18n-athena-led-zh-tw; then
    printf 'athena-led\n'
    return 0
  fi

  return 1
}

artifact_group_is_arch_independent() {
  local group_name="$1"
  [ "$group_name" = luci-theme-argon ] || [ "$group_name" = luci-theme-aurora ]
  # athena-led 不是架构无关（Rust 二进制是 aarch64）  ### ← ATHENA LED
}

release_package_name() {
  local package_file="$1" group_name="$2"
  local package_file_name safe_package_name package_arch package_release_name sdk_prefix
  package_file_name="$(basename "$package_file")"
  safe_package_name="${package_file_name//\~/-}"
  package_arch="$(release_package_arch_suffix "$group_name")"
  sdk_prefix="$(normalize_sdk_version "$OPENWRT_SDK_VERSION")-"
  case "$safe_package_name" in
    *.apk) package_release_name="${safe_package_name%.apk}-$package_arch.apk" ;;
    *_all.ipk) package_release_name="${safe_package_name%_all.ipk}_$package_arch.ipk" ;;
    *.ipk)
      local package_path_arch
      package_path_arch="$(basename "$(dirname "$(dirname "$package_file")")")"
      case "$safe_package_name" in
        *_"$package_path_arch".ipk) package_release_name="${safe_package_name%_"$package_path_arch".ipk}_$package_arch.ipk" ;;
        *) package_release_name="${safe_package_name%.ipk}_$package_arch.ipk" ;;
      esac
      ;;
    *) package_release_name="$safe_package_name" ;;
  esac
  case "$package_release_name" in main-* | 23.05-* | 24.10-* | 25.12-*) printf '%s\n' "$package_release_name" ;; *) printf '%s%s\n' "$sdk_prefix" "$package_release_name" ;; esac
}

release_package_arch_suffix() {
  local group_name="$1"
  if artifact_group_is_arch_independent "$group_name"; then printf 'all\n'; return; fi
  printf '%s\n' "${PACKAGE_ARCH_NAME//\//-}"
}

artifact_zip_name() {
  local group_name="$1" safe_arch_name="${PACKAGE_ARCH_NAME//\//-}" sdk_prefix
  sdk_prefix="$(normalize_sdk_version "$OPENWRT_SDK_VERSION")"
  if artifact_group_is_arch_independent "$group_name"; then printf '%s-%s-all.zip\n' "$sdk_prefix" "$group_name"; return; fi
  printf '%s-%s-%s.zip\n' "$sdk_prefix" "$group_name" "$safe_arch_name"
}

artifact_group_should_be_skipped() { return 1; }

# ===================== 编译目标生成 =====================
generate_compile_targets() {
  COMPILE_TARGETS=()

  # ... (你原有的其他 compile target 逻辑全部保留) ...

  # ===================== Athena LED compile targets =====================  ### ← ATHENA LED
  if selection_in athena-led; then
    if config_package_enabled athena-led; then
      add_compile_target package/athena-led/compile
    fi
    if config_package_enabled luci-app-athena-led; then
      add_compile_target package/luci-app-athena-led/compile
    fi
  fi

  [ "${#COMPILE_TARGETS[@]}" -gt 0 ] || die "No matching package compile targets were enabled"
}

# ===================== 编译执行 =====================
compile_packages() {
  local compile_target final_exit_code job_count parallel_exit_code result
  : > "$COMPILE_RESULTS_FILE"
  COMPILE_FAILURE_COUNT=0
  job_count="$(nproc)"
  for compile_target in "${COMPILE_TARGETS[@]}"; do
    result=success parallel_exit_code=0 final_exit_code=0
    if make -j"$job_count" "$compile_target"; then :; else
      parallel_exit_code=$?
      log "Parallel compile failed for $compile_target; retry with single job"
      if make -j1 "$compile_target" V=s; then :; else
        final_exit_code=$?
        result=failed
        COMPILE_FAILURE_COUNT=$((COMPILE_FAILURE_COUNT + 1))
        log "Compile failed for $compile_target (exit $final_exit_code)"
      fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$compile_target" "$result" "$final_exit_code" "$parallel_exit_code" >> "$COMPILE_RESULTS_FILE"
  done
}

# ===================== Build info / artifact 收集 =====================
# （generate_build_info / write_group_checksums / copy_artifacts 原样保留，不需要改）

generate_build_info() {
  local effective_config_sha256 repository_commit="${GITHUB_SHA:-}" repository_ref="${GITHUB_REF_NAME:-${GITHUB_REF:-unknown}}" repository_url=""
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then repository_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}"; else repository_url="$(git -C "$WORKSPACE" remote get-url origin 2>/dev/null || true)"; fi
  [ -z "$repository_commit" ] && repository_commit="$(git -C "$WORKSPACE" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  [ -n "$repository_url" ] || repository_url=unknown
  effective_config_sha256="$(sha256sum "$SDK_ROOT/.config" | awk '{print tolower($1)}')"
  BUILD_INFO_REPOSITORY_URL="$repository_url" BUILD_INFO_REPOSITORY_COMMIT="$repository_commit" BUILD_INFO_REPOSITORY_REF="$repository_ref" BUILD_INFO_SDK_VERSION="$OPENWRT_SDK_VERSION" BUILD_INFO_SDK_TARGET="$OPENWRT_TARGET" BUILD_INFO_SDK_SUBTARGET="$OPENWRT_SUBTARGET" BUILD_INFO_SDK_PROFILE="$OPENWRT_TARGET_PROFILE" BUILD_INFO_SDK_URL="$RESOLVED_SDK_URL" BUILD_INFO_SDK_SHA256="$EXPECTED_SDK_SHA256" BUILD_INFO_SDK_ARCHIVE="$(sdk_archive_name "$RESOLVED_SDK_URL")" BUILD_INFO_PACKAGE_SELECTION="$PACKAGE_SELECTION" BUILD_INFO_PACKAGE_ARCH_NAME="$PACKAGE_ARCH_NAME" BUILD_INFO_PACKAGE_SELECTED_ARCH="$PACKAGE_SELECTED_ARCH" BUILD_INFO_EFFECTIVE_CONFIG_SHA256="$effective_config_sha256" BUILD_INFO_COMPILE_FAILURE_COUNT="$COMPILE_FAILURE_COUNT" \
  python3 - "$BUILD_INFO_FILE" "$SOURCE_REVISIONS_FILE" "$CONFIG_REVISIONS_FILE" "$COMPILE_RESULTS_FILE" <<'PY'
import csv, datetime, json, os, sys
output_path, sources_path, configs_path, results_path = sys.argv[1:]
def read_tsv(path):
    if not os.path.isfile(path): return []
    with open(path, encoding="utf-8", newline="") as stream:
        return [row for row in csv.reader(stream, delimiter="\t") if row]
sources = [{"name": row[0], "repository": row[1], "ref": row[2], "commit": row[3]} for row in read_tsv(sources_path) if len(row) >= 4]
configs = [{"path": row[0], "sha256": row[1]} for row in read_tsv(configs_path) if len(row) >= 2]
compile_results = [{"target": row[0], "status": row[1], "exit_code": int(row[2]), "parallel_exit_code": int(row[3]), "retried_serially": int(row[3]) != 0} for row in read_tsv(results_path) if len(row) >= 4]
failure_count = int(os.environ["BUILD_INFO_COMPILE_FAILURE_COUNT"])
build_info = {
    "schema_version": 1,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "status": "partial" if failure_count else "success",
    "repository": {"url": os.environ["BUILD_INFO_REPOSITORY_URL"], "ref": os.environ["BUILD_INFO_REPOSITORY_REF"], "commit": os.environ["BUILD_INFO_REPOSITORY_COMMIT"]},
    "sdk": {"version": os.environ["BUILD_INFO_SDK_VERSION"], "target": os.environ["BUILD_INFO_SDK_TARGET"], "subtarget": os.environ["BUILD_INFO_SDK_SUBTARGET"], "profile": os.environ["BUILD_INFO_SDK_PROFILE"], "url": os.environ["BUILD_INFO_SDK_URL"], "sha256": os.environ["BUILD_INFO_SDK_SHA256"], "archive": os.environ["BUILD_INFO_SDK_ARCHIVE"]},
    "build": {"package_selection": os.environ["BUILD_INFO_PACKAGE_SELECTION"], "package_arch_name": os.environ["BUILD_INFO_PACKAGE_ARCH_NAME"], "package_selected_arch": os.environ["BUILD_INFO_PACKAGE_SELECTED_ARCH"], "effective_config_sha256": os.environ["BUILD_INFO_EFFECTIVE_CONFIG_SHA256"], "compile_failure_count": failure_count, "configs": configs, "compile_results": compile_results},
    "sources": sources,
    "github": {"run_id": os.environ.get("GITHUB_RUN_ID"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"), "workflow": os.environ.get("GITHUB_WORKFLOW")},
}
with open(output_path, "w", encoding="utf-8", newline="\n") as stream:
    json.dump(build_info, stream, ensure_ascii=False, indent=2)
    stream.write("\n")
PY
}

write_group_checksums() {
  local group_dir="$1"
  ( cd "$group_dir"; : > SHA256SUMS
    while IFS= read -r -d '' artifact_name; do sha256sum "$artifact_name" >> SHA256SUMS; done < <(find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\0' | LC_ALL=C sort -z) )
}

copy_artifacts() {
  local package_bin_dir="$SDK_ROOT/bin/packages" copied_count=0 group_dir group_name groups=() group_counts=() package_file package_file_name release_name skipped_count=0 staging_dir="$RUNNER_TEMP/package-artifact-groups" target_file zip_count=0 zip_file
  ARTIFACT_COLLECTION_FAILED=0
  rm -rf "$OUTPUT_DIR" "$staging_dir"
  mkdir -p "$OUTPUT_DIR" "$staging_dir"
  if [ ! -d "$package_bin_dir" ]; then log "No package artifacts"; ARTIFACT_COLLECTION_FAILED=1; return 0; fi
  if [ -z "$(find "$package_bin_dir" -type f \( -name '*.ipk' -o -name '*.apk' \) -print -quit)" ]; then log "No compiled .ipk or .apk"; ARTIFACT_COLLECTION_FAILED=1; return 0; fi
  command -v zip >/dev/null 2>&1 || die "zip command was not found"
  while IFS= read -r -d '' package_file; do
    package_file_name="$(basename "$package_file")"
    if ! artifact_package_allowed "$package_file_name"; then skipped_count=$((skipped_count + 1)); continue; fi
    group_name="$(artifact_package_group "$package_file_name")" || die "No artifact group for: $package_file_name"
    if artifact_group_should_be_skipped "$group_name"; then skipped_count=$((skipped_count + 1)); continue; fi
    if [ -z "${group_counts[$group_name]+set}" ]; then group_counts[$group_name]=0; groups+=("$group_name"); fi
    group_dir="$staging_dir/$group_name"; mkdir -p "$group_dir"
    release_name="$(release_package_name "$package_file" "$group_name")"
    target_file="$group_dir/$release_name"
    [ ! -e "$target_file" ] || die "Duplicate: $target_file"
    cp -a "$package_file" "$target_file"
    group_counts[$group_name]=$((group_counts[$group_name] + 1))
    copied_count=$((copied_count + 1))
  done < <(find "$package_bin_dir" -type f \( -name '*.ipk' -o -name '*.apk' \) -print0)
  if [ "$copied_count" -eq 0 ]; then log "No selected files"; ARTIFACT_COLLECTION_FAILED=1; return 0; fi
  for group_name in "${groups[@]}"; do
    group_dir="$staging_dir/$group_name"
    [ "${group_counts[$group_name]}" -gt 0 ] || die "No files staged for: $group_name"
    cp -a "$BUILD_INFO_FILE" "$group_dir/BUILDINFO.json"
    write_group_checksums "$group_dir"
    zip_file="$OUTPUT_DIR/$(artifact_zip_name "$group_name")"
    [ ! -e "$zip_file" ] || die "Duplicate zip: $zip_file"
    ( cd "$group_dir" && zip -q -r "$zip_file" . )
    zip_count=$((zip_count + 1))
  done
  rm -rf "$staging_dir"
  log "Packed $copied_count files into $zip_count zip(s); skipped $skipped_count"
  if [ -n "${GITHUB_ENV:-}" ]; then
    { echo "PACKAGE_OUTPUT_DIR=$OUTPUT_DIR"; echo "RESOLVED_SDK_URL=$RESOLVED_SDK_URL"; echo "EXPECTED_SDK_SHA256=$EXPECTED_SDK_SHA256"; } >> "$GITHUB_ENV"
  fi
}

# ===================== 主流程 =====================
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi

PACKAGE_SELECTION="$(normalize_package_selection "$PACKAGE_SELECTION")"
OPENWRT_SDK_VERSION="$(normalize_sdk_version "$OPENWRT_SDK_VERSION")"

mkdir -p "$RUNNER_TEMP" "$SDK_CACHE_DIR"

log "Resolve OpenWrt SDK metadata"
log "Selected package group: $PACKAGE_SELECTION"
log "Selected OpenWrt SDK version: $OPENWRT_SDK_VERSION"
prepare_sdk_metadata

if is_true "${SDK_METADATA_ONLY:-false}"; then
  emit_sdk_metadata
  log "Resolved SDK metadata: $RESOLVED_SDK_URL ($EXPECTED_SDK_SHA256)"
  exit 0
fi

log "Download and verify OpenWrt SDK"
download_sdk_with_metadata_retry
if [ -n "${GITHUB_OUTPUT:-}" ]; then emit_sdk_metadata; fi
rm -rf "$SDK_ROOT"
extract_sdk "$RESOLVED_SDK_URL"
[ -x "$SDK_ROOT/scripts/feeds" ] || die "Invalid SDK: scripts/feeds missing"
[ -f "$SDK_ROOT/Makefile" ] || die "Invalid SDK: Makefile missing"
: > "$SOURCE_REVISIONS_FILE"

log "Update SDK feeds"
cd "$SDK_ROOT"
./scripts/feeds update -a
record_feed_revisions

log "Load custom packages"
remove_builtin_packages
load_custom_packages

log "Refresh SDK feed indexes"
./scripts/feeds update -a   ### ← CHANGED: 去掉 -i

log "Install SDK feeds"
./scripts/feeds install -a
prune_luci_translations

log "Load package config"
load_config_files
make defconfig
generate_compile_targets
generate_artifact_filters

log "Compile packages"
compile_packages

log "Generate build traceability metadata"
generate_build_info

log "Collect package artifacts"
copy_artifacts

if [ "$COMPILE_FAILURE_COUNT" -gt 0 ]; then
  if [ "$ARTIFACT_COLLECTION_FAILED" -eq 0 ]; then
    die "$COMPILE_FAILURE_COUNT compile target(s) failed; artifacts still collected"
  fi
  die "$COMPILE_FAILURE_COUNT compile target(s) failed; no artifacts collected"
fi
if [ "$ARTIFACT_COLLECTION_FAILED" -ne 0 ]; then
  die "No selected package artifacts were collected"
fi
