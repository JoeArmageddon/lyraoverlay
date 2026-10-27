#!/usr/bin/env bash
# Audits font files and installs the ones that pass into the project's Fonts/ folder.
#
#   Scripts/install-fonts.sh                     audits and installs everything in Fonts/drawn
#   Scripts/install-fonts.sh path/to/A.ttf dir/  audits the given .ttf/.otf files and folders
#   Scripts/install-fonts.sh --check             audits Fonts/ itself and copies nothing
#
# Runs from any directory. Only passing fonts are copied (an older copy with the same file name is
# overwritten); Fonts/drawn is only ever read. Partial files (*.tmp*) and unreadable files are skipped.
# The checks are the same ones the test target runs over Fonts/ (LyraApp/Tests/LyraRenderTests/FontAudit.swift).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FONTS="$ROOT/Fonts"

CHECK_ONLY=0
INPUTS=()
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) INPUTS+=("$arg") ;;
    esac
done
if [ "$CHECK_ONLY" = 1 ] && [ ${#INPUTS[@]} -eq 0 ]; then INPUTS=("$FONTS"); fi
if [ ${#INPUTS[@]} -eq 0 ]; then INPUTS=("$FONTS/drawn"); fi
mkdir -p "$FONTS"

# ---- Collect candidate files ------------------------------------------------------------------
CANDIDATES=()
SKIPPED=()   # "file<TAB>reason"
add_file() {
    local f="$1" base
    base="$(basename "$f")"
    case "$base" in
        *.tmp*|*.partial|.*) SKIPPED+=("$f"$'\t'"partial or hidden file"); return ;;
    esac
    case "$(printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]')" in
        ttf|otf) ;;
        *) return ;;   # specimens, scripts, READMEs: not fonts, not worth a row
    esac
    if [ ! -r "$f" ] || [ ! -s "$f" ]; then SKIPPED+=("$f"$'\t'"unreadable or empty"); return; fi
    CANDIDATES+=("$f")
}
for input in "${INPUTS[@]}"; do
    if [ -d "$input" ]; then
        depth=(); [ "$(cd "$input" && pwd)" = "$FONTS" ] && depth=(-maxdepth 1)   # Fonts/ itself: never descend into drawn/
        while IFS= read -r f; do add_file "$f"; done < <(find "$input" ${depth[@]+"${depth[@]}"} -type f \( -iname '*.ttf' -o -iname '*.otf' \) | sort)
    elif [ -f "$input" ]; then
        add_file "$input"
    else
        echo "warning: $input does not exist" >&2
    fi
done

# ---- The auditor (compiled once, cached) ------------------------------------------------------
AUDIT_SRC="$(mktemp -d)/audit.swift"
cat > "$AUDIT_SRC" <<'SWIFT'
import Foundation
import CoreText

// usage: audit <fontsDir> <file>...
// (glyph bounds allow 2 units of rounding past 1.0 em / -0.4 em)
// prints one line per file: STATUS \t path \t postScript \t family \t problems (separated by "; ")
let args = Array(CommandLine.arguments.dropFirst())
let fontsDir = URL(fileURLWithPath: args[0])
let files = args.dropFirst().map { URL(fileURLWithPath: $0) }

func descriptor(_ url: URL) -> CTFontDescriptor? {
    (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
}
func ps(_ d: CTFontDescriptor) -> String? { CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String }

// PostScript names already in Fonts/ under a file name that is not being replaced by this run.
let incoming = Set(files.map { $0.lastPathComponent })
var existing: [String: String] = [:]
for url in (try? FileManager.default.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil)) ?? []
where ["ttf", "otf"].contains(url.pathExtension.lowercased()) && !incoming.contains(url.lastPathComponent) {
    if let d = descriptor(url), let name = ps(d) { existing[name] = url.lastPathComponent }
}

var required: [Character] = []
for u in UnicodeScalar("A").value...UnicodeScalar("Z").value { required.append(Character(UnicodeScalar(u)!)) }
for u in UnicodeScalar("a").value...UnicodeScalar("z").value { required.append(Character(UnicodeScalar(u)!)) }
required += Array("0123456789.,!?'\"-:;&()/#@%+=$*_~")
required += Array("áàâäãåéèêëíìîïóòôöõúùûüñçýÿÁÀÂÄÃÅÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇÝ")

var seenInBatch: [String: String] = [:]
for url in files {
    var problems: [String] = []
    guard let d = descriptor(url) else {
        print("FAIL\t\(url.path)\t-\t-\tnot a font CoreText can read"); continue
    }
    let name = ps(d) ?? ""
    let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String ?? ""
    if name.isEmpty { problems.append("no PostScript name") }
    if family.isEmpty { problems.append("no family name") }
    if let other = existing[name] { problems.append("PostScript name \(name) already used by Fonts/\(other)") }
    if let other = seenInBatch[name] { problems.append("PostScript name \(name) also in \(other)") }
    seenInBatch[name] = url.lastPathComponent

    let ct = CTFontCreateWithFontDescriptor(d, 1000, nil)
    let copyright = (CTFontCopyName(ct, kCTFontCopyrightNameKey) as String?) ?? ""
    let license = (CTFontCopyName(ct, kCTFontLicenseNameKey) as String?) ?? ""
    if copyright.isEmpty { problems.append("no copyright string") }
    if !license.contains("SIL Open Font License") { problems.append("license text lacks \"SIL Open Font License\"") }
    if CTFontGetUnitsPerEm(ct) != 1000 { problems.append("unitsPerEm \(CTFontGetUnitsPerEm(ct)) (want 1000)") }
    let asc = CTFontGetAscent(ct), desc = CTFontGetDescent(ct)
    if abs(asc - 800) > 20 { problems.append("ascent \(Int(asc)) (want about 800)") }
    if abs(desc - 200) > 20 { problems.append("descent \(Int(desc)) (want about 200)") }

    var missing: [Character] = [], tall: [String] = [], deep: [String] = [], narrow: [Character] = []
    for ch in required {
        let units = Array(String(ch).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(ct, units, &glyphs, units.count) else { missing.append(ch); continue }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ct, .horizontal, &glyphs, &advance, 1)
        if advance.width <= 0 { narrow.append(ch) }
        if let box = CTFontCreatePathForGlyph(ct, glyphs[0], nil)?.boundingBoxOfPath, !box.isNull, !box.isEmpty {
            if box.maxY > 1002 { tall.append("\(ch)=\(Int(box.maxY))") }
            if box.minY < -402 { deep.append("\(ch)=\(Int(box.minY))") }
        }
    }
    if !missing.isEmpty { problems.append("missing glyphs: \(String(missing))") }
    if !narrow.isEmpty { problems.append("non-positive advance: \(String(narrow))") }
    if !tall.isEmpty { problems.append("rises past 1.0 em: \(tall.joined(separator: ","))") }
    if !deep.isEmpty { problems.append("sinks below -0.4 em: \(deep.joined(separator: ","))") }
    print("\(problems.isEmpty ? "OK" : "FAIL")\t\(url.path)\t\(name)\t\(family)\t\(problems.joined(separator: "; "))")
}
SWIFT

CACHE="${TMPDIR:-/tmp}/lyra-font-audit"
mkdir -p "$CACHE"
SUM="$(shasum "$AUDIT_SRC" | cut -c1-12)"
AUDIT_BIN="$CACHE/audit-$SUM"
if [ ! -x "$AUDIT_BIN" ]; then
    echo "==> Compiling the font auditor (first run only)"
    swiftc -O -o "$AUDIT_BIN" "$AUDIT_SRC" 2>&1 | sed 's/^/    /' >&2 || true
fi
[ -x "$AUDIT_BIN" ] || { echo "error: could not compile the auditor (is Xcode or the Swift toolchain installed?)" >&2; exit 1; }

# ---- Audit, then copy -------------------------------------------------------------------------
ROWS=()   # "STATUS<TAB>name<TAB>postscript<TAB>detail"
INSTALLED=0; UPDATED=0; UNCHANGED=0; FAILED=0

echo "==> Auditing ${#CANDIDATES[@]} font file(s)"
if [ ${#CANDIDATES[@]} -gt 0 ]; then
    RESULTS="$("$AUDIT_BIN" "$FONTS" "${CANDIDATES[@]}")"
    while IFS=$'\t' read -r status path psname family problems; do
        [ -n "$status" ] || continue
        base="$(basename "$path")"
        if [ "$status" != "OK" ]; then
            ROWS+=("skipped"$'\t'"$base"$'\t'"$psname"$'\t'"$problems"); FAILED=$((FAILED + 1)); continue
        fi
        dest="$FONTS/$base"
        if [ "$CHECK_ONLY" = 1 ] || [ "$(cd "$(dirname "$path")" && pwd)/$base" = "$dest" ]; then
            ROWS+=("ok"$'\t'"$base"$'\t'"$psname"$'\t'"$family (audit only)"); continue
        fi
        if [ ! -e "$dest" ]; then
            cp "$path" "$dest"; INSTALLED=$((INSTALLED + 1)); ROWS+=("installed"$'\t'"$base"$'\t'"$psname"$'\t'"$family")
        elif cmp -s "$path" "$dest"; then
            UNCHANGED=$((UNCHANGED + 1)); ROWS+=("unchanged"$'\t'"$base"$'\t'"$psname"$'\t'"$family")
        else
            cp "$path" "$dest"; UPDATED=$((UPDATED + 1)); ROWS+=("updated"$'\t'"$base"$'\t'"$psname"$'\t'"$family (replaced older copy)")
        fi
    done <<< "$RESULTS"
fi
for entry in "${SKIPPED[@]+"${SKIPPED[@]}"}"; do
    IFS=$'\t' read -r path reason <<< "$entry"
    ROWS+=("skipped"$'\t'"$(basename "$path")"$'\t'"-"$'\t'"$reason")
done

echo
printf '%-10s %-34s %-34s %s\n' STATUS FILE POSTSCRIPT DETAIL
for row in "${ROWS[@]+"${ROWS[@]}"}"; do
    IFS=$'\t' read -r s f p d <<< "$row"
    printf '%-10s %-34s %-34s %s\n' "$s" "$f" "$p" "$d"
done
echo
echo "installed: $INSTALLED   updated: $UPDATED   unchanged: $UNCHANGED   skipped: $((FAILED + ${#SKIPPED[@]}))"
if [ "$CHECK_ONLY" = 0 ] && [ $((INSTALLED + UPDATED)) -gt 0 ]; then
    echo "Next: add a theme for any new font in LyraCore/Sources/LyraCore/Theme/Theme.swift, then run the tests."
fi
[ "$FAILED" -eq 0 ] || exit 2
