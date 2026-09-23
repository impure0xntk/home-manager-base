import argparse
import os
import re
import sys


def parse_proguard_mapping(mapping_path: str):
    """
    Parses a ProGuard mapping.txt file to extract class and method obfuscation maps.

    Args:
        mapping_path (str): The path to the ProGuard mapping file.

    Returns:
        tuple: A dictionary for class mappings (orig -> obf) and a dictionary
               for method mappings ((orig_class, orig_method, args_tuple) -> obf_method).
    """
    class_map = {}  # original_class -> obfuscated_class
    method_map = {}  # (original_class, original_method, args_tuple) -> obfuscated_method

    class_pattern = re.compile(r"^([\w.]+)\s+->\s+([\w.]+):$")
    method_pattern = re.compile(
        r"^(?:\d+:\d+:)?(?:[\w.<>]+)\s+([\w<>]+)\(([^)]*)\)\s+->\s+([\w<>]+)$"
    )

    current_orig_class = None

    with open(mapping_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            # Match class line
            class_match = class_pattern.match(line)
            if class_match:
                current_orig_class = class_match.group(1)
                obfuscated_class = class_match.group(2)
                class_map[current_orig_class] = obfuscated_class
                continue

            # Match method line
            method_match = method_pattern.match(line)
            if method_match and current_orig_class:
                orig_method = method_match.group(1)
                args_str = method_match.group(2)
                obf_method = method_match.group(3)

                # Split args and remove spaces, e.g., "int, java.lang.String" -> ("int", "java.lang.String")
                args_list = (
                    [arg.strip() for arg in args_str.split(",")] if args_str else []
                )
                args_tuple = tuple(args_list)
                method_map[(current_orig_class, orig_method, args_tuple)] = obf_method

    return class_map, method_map


def replace_classes_in_text(text: str, class_map: dict, verbose: bool = False) -> str:
    """
    Scans and replaces fully qualified class names within a string block.

    Args:
        text (str): The input text block (e.g., inside a DO section).
        class_map (dict): The class mapping dictionary.
        verbose (bool): Enabling detailed conversion output.

    Returns:
        str: The text block with obfuscated class names.
    """
    # Sort by length descending to prevent partial match replacement issues
    sorted_classes = sorted(class_map.keys(), key=len, reverse=True)

    for orig_class in sorted_classes:
        # Enforce boundary checking using negative lookbehind/lookahead to prevent partial word matches
        pattern = r"(?<![\w.])" + re.escape(orig_class) + r"(?![\w.])"
        if verbose and re.search(pattern, text):
            print(
                f"  [Verbose] Replacing class in DO body: {orig_class} -> {class_map[orig_class]}",
                file=sys.stderr,
            )
        text = re.sub(pattern, class_map[orig_class], text)
    return text


def convert_byteman_stream(
    input_stream,
    output_stream,
    class_map: dict,
    method_map: dict,
    verbose: bool = False,
):
    """
    Reads from an input stream, updates targeted signatures and DO blocks using mapped names,
    and writes out to an output stream.

    Args:
        input_stream: Readable stream object (file or sys.stdin).
        output_stream: Writable stream object (file or sys.stdout).
        class_map (dict): Extracted class obfuscation mappings.
        method_map (dict): Extracted method obfuscation mappings.
        verbose (bool): Enabled detailed conversion output.
    """
    current_class = None
    in_do_section = False

    class_regex = re.compile(r"^(\s*CLASS\s+)([\w.]+)(.*)$", re.IGNORECASE)
    interface_regex = re.compile(r"^(\s*INTERFACE\s+)([\w.]+)(.*)$", re.IGNORECASE)
    method_regex = re.compile(
        r"^(\s*METHOD\s+)([\w<>]+)(?:\(([^)]*)\))?(.*)$", re.IGNORECASE
    )

    do_regex = re.compile(r"^(\s*DO\s+)(.*)$", re.IGNORECASE)
    endrule_regex = re.compile(r"^(\s*ENDRULE\s*)$", re.IGNORECASE)

    for line in input_stream:
        # --- Handle DO section internal body ---
        if in_do_section:
            if endrule_regex.match(line):
                in_do_section = False
                output_stream.write(line)
            else:
                converted_line = replace_classes_in_text(line, class_map, verbose)
                output_stream.write(converted_line)
            continue

        # --- Handle Standard Definition Lines ---
        # 1. Match and convert CLASS / INTERFACE
        class_match = class_regex.match(line) or interface_regex.match(line)
        if class_match:
            prefix, orig_class, suffix = class_match.groups()
            current_class = orig_class

            if orig_class in class_map:
                obf_class = class_map[orig_class]
                if verbose:
                    print(
                        f"[Verbose] Converting structural class line: {orig_class} -> {obf_class}",
                        file=sys.stderr,
                    )
                line = f"{prefix}{obf_class}{suffix}\n"
            output_stream.write(line)
            continue

        # 2. Match and convert METHOD signatures
        method_match = method_regex.match(line)
        if method_match and current_class:
            prefix, orig_method, args_str, suffix = method_match.groups()
            obf_method = None

            if args_str is not None:
                # Precise signature lookup based on specified arguments
                args_list = (
                    [arg.strip() for arg in args_str.split(",")]
                    if args_str.strip()
                    else []
                )
                args_tuple = tuple(args_list)
                obf_method = method_map.get((current_class, orig_method, args_tuple))
            else:
                # Fallback lookup if Byteman rule omits argument definitions
                for (c, m, a), obf in method_map.items():
                    if c == current_class and m == orig_method:
                        obf_method = obf
                        break

            if obf_method:
                if verbose:
                    print(
                        f"[Verbose] Converting structural method signature: {orig_method} -> {obf_method}",
                        file=sys.stderr,
                    )

                if args_str is not None:
                    # Also obf-map custom class types inside the argument listing
                    obf_args_list = []
                    for arg in args_list:
                        base_arg = arg.replace("[]", "")  # Handle arrays cleanly
                        if base_arg in class_map:
                            obf_args_list.append(
                                arg.replace(base_arg, class_map[base_arg])
                            )
                        else:
                            obf_args_list.append(arg)
                    obf_args_str = ", ".join(obf_args_list)
                    line = f"{prefix}{obf_method}({obf_args_str}){suffix}\n"
                else:
                    line = f"{prefix}{obf_method}{suffix}\n"

            output_stream.write(line)
            continue

        # 3. Detect DO action section trigger
        do_match = do_regex.match(line)
        if do_match:
            in_do_section = True
            prefix, rest_of_line = do_match.groups()
            # Process trailing inline expressions on the same line as DO keyword
            converted_rest = replace_classes_in_text(rest_of_line, class_map, verbose)
            output_stream.write(f"{prefix}{converted_rest}\n")
            continue

        # Forward unmodified fallback lines (RULE, AT, BIND, comments, etc.)
        output_stream.write(line)


def main():
    parser = argparse.ArgumentParser(
        description="Obfuscates Byteman script files (.btm) using a ProGuard mapping.txt file. "
        "Converts CLASS, INTERFACE, METHOD structures, and class names referenced within DO blocks. "
        "Supports standard input/output streams when files are omitted."
    )
    parser.add_argument(
        "-m", "--mapping", required=True, help="Path to the ProGuard mapping.txt file."
    )
    parser.add_argument(
        "-i",
        "--input",
        help="Path to the original Byteman .btm input file. If omitted, reads from stdin.",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="Path to output the converted Byteman file. If omitted, writes to stdout.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Print detailed transformation trace info to stderr.",
    )

    args = parser.parse_args()

    # Validate mapping file presence
    if not os.path.exists(args.mapping):
        print(
            f"Error: ProGuard mapping file not found at '{args.mapping}'",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.verbose:
        print("Parsing ProGuard mapping information...", file=sys.stderr)

    c_map, m_map = parse_proguard_mapping(args.mapping)

    if args.verbose:
        print(
            f"Loaded {len(c_map)} classes and {len(m_map)} methods from mapping.",
            file=sys.stderr,
        )

    # Determine input stream (file or stdin)
    if args.input:
        if not os.path.exists(args.input):
            print(
                f"Error: Input Byteman file not found at '{args.input}'",
                file=sys.stderr,
            )
            sys.exit(1)
        input_stream = open(args.input, encoding="utf-8")
        if args.verbose:
            print(f"Reading Byteman script from file: '{args.input}'", file=sys.stderr)
    else:
        input_stream = sys.stdin
        if args.verbose:
            print("Reading Byteman script from stdin...", file=sys.stderr)

    # Determine output stream (file or stdout)
    if args.output:
        output_stream = open(args.output, "w", encoding="utf-8")
        if args.verbose:
            print(f"Writing converted script to file: '{args.output}'", file=sys.stderr)
    else:
        output_stream = sys.stdout

    try:
        convert_byteman_stream(input_stream, output_stream, c_map, m_map, args.verbose)
    finally:
        # Securely close streams if they are files
        if args.input:
            input_stream.close()
        if args.output:
            output_stream.close()
        if args.verbose:
            print("Transformation completed successfully.", file=sys.stderr)


if __name__ == "__main__":
    main()
