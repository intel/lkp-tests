#!/usr/bin/env python3

import argparse
import difflib
import subprocess
import tempfile
import time
from pathlib import Path
from contextlib import contextmanager
from typing import Iterator


class Args(argparse.Namespace):
    linux_src: Path
    rust_project_diff: Path


def parse_args() -> Args:
    parser = argparse.ArgumentParser()
    parser.add_argument("--linux-src", required=True, type=Path)
    parser.add_argument("--rust-project-diff", required=True, type=Path)
    return parser.parse_args(namespace=Args())


def generate_rust_project(src_dir: Path, build_dir: Path) -> None:
    # Build a minimal config with Rust enabled, then emit rust-project.json.
    build_dir.mkdir(parents=True, exist_ok=True)

    base_make = (
        "make",
        f"O={build_dir}",
    )
    for args in (
        (*base_make, "allmodconfig"),
        (*base_make, "olddefconfig"),
        (
            "scripts/config",
            "--file",
            build_dir / ".config",
            "--enable",
            "CONFIG_RUST",
            "--enable",
            "CONFIG_RANDSTRUCT_NONE",
        ),
        (*base_make, "rust-analyzer"),
    ):
        subprocess.run(args, cwd=src_dir, check=True)


@contextmanager
def with_worktree(worktree_dir: Path, linux_src: Path) -> Iterator[None]:
    subprocess.run(
        ("git", "worktree", "add", worktree_dir),
        cwd=linux_src,
        check=True,
    )
    try:
        yield
    finally:
        subprocess.run(
            ("git", "worktree", "remove", worktree_dir),
            cwd=linux_src,
            check=True,
        )


def collect_rust_project(
    source_dir: Path,
    build_dir: Path,
    commit: str,
) -> tuple[list[str], str, str, int]:
    subprocess.run(
        ("git", "checkout", "--detach", commit),
        cwd=source_dir,
        check=True,
    )
    generate_rust_project(source_dir, build_dir)
    project = build_dir / "rust-project.json"
    with project.open() as project_file:
        lines = project_file.readlines()
    path_label = str(project)

    start = time.monotonic_ns()
    result = subprocess.run(
        ("rust-analyzer", "analysis-stats", project),
        capture_output=True,
        check=True,
        text=True,
    )
    end = time.monotonic_ns()

    return lines, path_label, result.stdout, end - start


def main() -> int:
    args = parse_args()

    rust_project_diff = args.rust_project_diff
    rust_project_diff.parent.mkdir(parents=True, exist_ok=True)

    linux_src = args.linux_src
    assert linux_src.is_dir(), f"linux source not found: {linux_src}"

    # Use a single directory tree for both builds to avoid spurious diffs from
    # paths leaking into the rust-project.json.
    with tempfile.TemporaryDirectory(prefix="rust-analyzer-") as workdir_str:
        workdir = Path(workdir_str)
        source_dir = workdir / "source"
        build_dir = workdir / "build"
        with with_worktree(source_dir, linux_src):
            head_lines, head_path_label, head_stdout, head_elapsed_ns = (
                collect_rust_project(source_dir, build_dir, "HEAD")
            )
            base_lines, base_path_label, base_stdout, base_elapsed_ns = (
                collect_rust_project(source_dir, build_dir, "HEAD~1")
            )

    diff = difflib.unified_diff(
        base_lines,
        head_lines,
        fromfile=base_path_label,
        tofile=head_path_label,
    )

    with rust_project_diff.open("w") as diff_out:
        diff_out.writelines(diff)

    print("rust-analyzer.success: 1")
    print(f"rust-analyzer.head_elapsed_ms: {head_elapsed_ns / 1e6}")
    print(f"rust-analyzer.base_elapsed_ms: {base_elapsed_ns / 1e6}")
    print(f"rust-analyzer.head_stdout: {head_stdout}")
    print(f"rust-analyzer.base_stdout: {base_stdout}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
