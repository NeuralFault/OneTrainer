#!/usr/bin/env python3
"""
Detects AMD Radeon GPU GFX architecture strings on Windows.

Usage modes:
  (default)   Auto-selects the highest-priority supported GPU, prints its gfx arch to stdout, exits 0.
  --list      Prints all supported GPUs as 'arch|name' lines (for bat script menus), exits 0.
  --pick N    Prints the gfx arch for the Nth GPU from --list (1-based), exits 0.

Exits 1 with an error message to stderr if no supported AMD GPU is found.
"""
import subprocess
import sys

# Generic iGPU name patterns — Ryzen APUs that report no model number.
# These are deprioritised vs named dGPUs and treated as unsupported if alone.
_GENERIC_IGPU_PATTERNS = (
    # Ryzen 4000/5000 (Renoir/Cezanne), 7000 (Raphael), 9000 (Granite Ridge)
    # desktop iGPUs — all report no model suffix, 2 CU RDNA 2, not worth supporting
    "amd radeon graphics",
    "amd radeon(tm) graphics",
    "radeon graphics",
    # Raven Ridge / Picasso era Vega iGPUs
    "amd radeon vega",
    "radeon vega",
)


def _is_generic_igpu(name: str) -> bool:
    """Return True if the adapter name looks like a generic, un-numbered iGPU."""
    lower = name.lower()
    return any(lower.startswith(pat) or lower == pat for pat in _GENERIC_IGPU_PATTERNS)


def get_gpu_names() -> list[str]:
    """Query Windows display adapter names via PowerShell/WMI.

    Returns adapter names sorted so that named dGPUs come before generic iGPUs.
    Within each group, adapters with more reported VRAM come first.
    """
    try:
        # Fetch Name + AdapterRAM together so we can use RAM as a sort hint.
        # AdapterRAM is uint32 and overflows for >4 GB cards, but it still
        # reliably distinguishes dGPUs (large / overflowed) from iGPUs (0 or small).
        cmd = (
            "Get-WmiObject Win32_VideoController "
            "| Select-Object Name, AdapterRAM "
            "| ForEach-Object { $_.Name + '|' + $_.AdapterRAM }"
        )
        result = subprocess.run(
            ["powershell", "-NoProfile", "-Command", cmd],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode != 0:
            return []

        entries: list[tuple[str, int]] = []
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.rsplit("|", 1)
            name = parts[0].strip()
            try:
                ram = int(parts[1].strip()) if len(parts) == 2 else 0
            except ValueError:
                ram = 0
            entries.append((name, ram))

        # Sort: non-generic (dGPU / named iGPU) first, generic iGPU last.
        # Secondary key: more reported VRAM first (helps prefer dGPU when names tie).
        entries.sort(key=lambda e: (_is_generic_igpu(e[0]), -e[1]))
        return [name for name, _ in entries]
    except Exception as e:
        print(f"ERROR: Failed to query GPU info: {e}", file=sys.stderr)
        return []


def get_gfx_arch(name: str) -> str | None:
    """Map an AMD GPU display name to its ROCm GFX architecture string.

    Returns the gfx arch (e.g. 'gfx1100') or None if unrecognised / not AMD.
    """
    lower = name.lower()
    if "amd" not in lower and "radeon" not in lower:
        return None

    ns = name.replace(" ", "")  # no-spaces variant for models like 'RX7800'

    def has(s: str) -> bool:
        return s.lower() in lower

    def has_ns(s: str) -> bool:
        return s.replace(" ", "").lower() in ns.lower()

    # ── RDNA 4 ────────────────────────────────────────────────────────────────
    if has("R9700") or has("R9600") or has("9070"):
        return "gfx1201"
    if has("9060"):
        return "gfx1200"

    # ── RDNA 3.5 APUs ─────────────────────────────────────────────────────────
    if has("860M"):
        return "gfx1152"
    if has("890M"):
        return "gfx1150"
    if has("8040S") or has("8050S") or has("8060S") or has("880M") or has("Z2 Extreme"):
        return "gfx1151"

    # ── RDNA 3 APUs (Phoenix) ─────────────────────────────────────────────────
    if has("740M") or has("760M") or has("780M") or has("Z1") or has("Z2"):
        return "gfx1103"

    # ── RDNA 3 dGPU Navi33 ────────────────────────────────────────────────────
    if has("7400") or has("7500") or has("7600") or has("7650") or has("7700S"):
        return "gfx1102"

    # ── RDNA 3 dGPU Navi32 ────────────────────────────────────────────────────
    if has("7700") or has("RX 7800") or has("v710") or has_ns("RX7800"):
        return "gfx1101"

    # ── RDNA 3 dGPU Navi31 (incl. Pro) ───────────────────────────────────────
    if has("W7800") or has("7900") or has("7950") or has("7990"):
        return "gfx1100"

    # ── RDNA 2 APUs (Rembrandt) ───────────────────────────────────────────────
    if has("660M") or has("680M"):
        return "gfx1035"

    # ── RDNA 2 Navi24 (low-end / mobile) ─────────────────────────────────────
    if (
        has("6300") or has("6400") or has("6450")
        or has("6500") or has("6550") or has("6500M")
    ):
        return "gfx1034"

    # ── RDNA 2 Steam Deck APU ─────────────────────────────────────────────────
    if has("Van Gogh") or has("Sephiroth"):
        return "gfx1033"

    # ── RDNA 2 Navi23 ────────────────────────────────────────────────────────
    if has("6600") or has("6650") or has("6700S") or has("6800S") or has("6600M"):
        return "gfx1032"

    # ── RDNA 2 Navi22 (note: desktop 6800 is Navi21/gfx1030, not here) ───────
    if has("6700") or has("6750") or has("6800M") or has("6850M"):
        return "gfx1031"

    # ── RDNA 2 Navi21 (big die) ───────────────────────────────────────────────
    if has("6800") or has("6900") or has("6950") or has("v620"):
        return "gfx1030"

    # ── RDNA 1 Navi10 XTX ────────────────────────────────────────────────────
    if has("5500"):
        return "gfx1012"

    # ── RDNA 1 Pro ───────────────────────────────────────────────────────────
    if has("v520"):
        return "gfx1011"

    # ── RDNA 1 Navi10 XT ─────────────────────────────────────────────────────
    if has("5600") or has("5700"):
        return "gfx1010"

    # Vega / GCN5 cards (gfx900, gfx906) are intentionally not supported.

    return None


def get_supported_gpus() -> list[tuple[str, str]]:
    """Return (name, arch) pairs for every supported AMD GPU, dGPUs first."""
    gpu_names = get_gpu_names()
    return [(name, arch) for name in gpu_names if (arch := get_gfx_arch(name))]


def _print_detection_errors(gpu_names: list[str]) -> None:
    """Print appropriate error messages when no supported GPU could be resolved."""
    amd_gpus = [n for n in gpu_names if "amd" in n.lower() or "radeon" in n.lower()]
    generic_igpus = [n for n in amd_gpus if _is_generic_igpu(n)]
    unknown_named = [n for n in amd_gpus if not _is_generic_igpu(n)]

    if generic_igpus and not unknown_named:
        print("ERROR: Only an unsupported integrated GPU was detected:", file=sys.stderr)
        for g in generic_igpus:
            print(f"  - {g}", file=sys.stderr)
        print(
            "Integrated AMD graphics (e.g. Ryzen APU iGPUs) are not supported by this project.",
            file=sys.stderr,
        )
    elif unknown_named:
        print("ERROR: AMD GPU(s) detected but no supported GFX arch mapping found:", file=sys.stderr)
        for g in unknown_named:
            print(f"  - {g}", file=sys.stderr)
        print(
            "Please open an issue at https://github.com/Nerogar/OneTrainer "
            "including your exact GPU model name so the mapping can be added.",
            file=sys.stderr,
        )
    else:
        print("ERROR: No AMD/Radeon GPU found among the detected adapters:", file=sys.stderr)
        for n in gpu_names:
            print(f"  - {n}", file=sys.stderr)


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--list", action="store_true",
                        help="Print all supported GPUs as 'arch|name' lines and exit.")
    parser.add_argument("--pick", type=int, default=None, metavar="N",
                        help="Print the arch for the Nth GPU from --list (1-based) and exit.")
    args, _ = parser.parse_known_args()

    gpu_names = get_gpu_names()

    if not gpu_names:
        print("ERROR: No display adapters found via WMI.", file=sys.stderr)
        sys.exit(1)

    supported = get_supported_gpus()

    if args.list:
        # Print all supported GPUs as 'arch|name' for the bat menu.
        if not supported:
            _print_detection_errors(gpu_names)
            sys.exit(1)
        for name, arch in supported:
            print(f"{arch}|{name}")
        sys.exit(0)

    if args.pick is not None:
        if not supported:
            _print_detection_errors(gpu_names)
            sys.exit(1)
        idx = args.pick - 1  # 1-based → 0-based
        if idx < 0 or idx >= len(supported):
            print(
                f"ERROR: Invalid selection {args.pick}. Must be between 1 and {len(supported)}.",
                file=sys.stderr,
            )
            sys.exit(1)
        name, arch = supported[idx]
        print(arch)
        sys.exit(0)

    # Default: auto-pick the first (highest-priority) supported GPU.
    if supported:
        name, arch = supported[0]
        print(arch)
        sys.exit(0)

    _print_detection_errors(gpu_names)
    sys.exit(1)


if __name__ == "__main__":
    main()
