"""Small built-in PDF fallback for local exports."""

from __future__ import annotations

from pathlib import Path


def _pdf_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def write_simple_pdf(text: str, output_path: Path, title: str = "Autonovel Manuscript") -> Path:
    """Write a valid, plain PDF without external system dependencies."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    words = text.split()
    lines: list[str] = []
    current: list[str] = []
    current_len = 0
    for word in words:
        if current_len + len(word) + 1 > 82:
            lines.append(" ".join(current))
            current = [word]
            current_len = len(word)
        else:
            current.append(word)
            current_len += len(word) + 1
    if current:
        lines.append(" ".join(current))

    page_chunks = [lines[i:i + 44] for i in range(0, len(lines), 44)] or [[]]
    objects: list[bytes] = []
    page_object_numbers: list[int] = []

    def add_object(body: str) -> int:
        objects.append(body.encode("latin-1", errors="replace"))
        return len(objects)

    catalog_num = add_object("<< /Type /Catalog /Pages 2 0 R >>")
    pages_num = add_object("PAGES")
    font_num = add_object("<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>")

    for page_lines in page_chunks:
        content_lines = ["BT", "/F1 11 Tf", "72 742 Td", "14 TL"]
        for index, line in enumerate(page_lines):
            prefix = "" if index == 0 else "T* "
            content_lines.append(f"{prefix}({_pdf_escape(line)}) Tj")
        content_lines.append("ET")
        stream = "\n".join(content_lines)
        content_num = add_object(f"<< /Length {len(stream.encode('latin-1', errors='replace'))} >>\nstream\n{stream}\nendstream")
        page_num = add_object(
            f"<< /Type /Page /Parent {pages_num} 0 R /MediaBox [0 0 612 792] "
            f"/Resources << /Font << /F1 {font_num} 0 R >> >> /Contents {content_num} 0 R >>"
        )
        page_object_numbers.append(page_num)

    kids = " ".join(f"{num} 0 R" for num in page_object_numbers)
    objects[pages_num - 1] = f"<< /Type /Pages /Kids [{kids}] /Count {len(page_object_numbers)} >>".encode()

    info_num = add_object(f"<< /Title ({_pdf_escape(title)}) /Producer (Autonovel) >>")

    output = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for index, body in enumerate(objects, start=1):
        offsets.append(len(output))
        output.extend(f"{index} 0 obj\n".encode())
        output.extend(body)
        output.extend(b"\nendobj\n")
    xref_offset = len(output)
    output.extend(f"xref\n0 {len(objects) + 1}\n".encode())
    output.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        output.extend(f"{offset:010d} 00000 n \n".encode())
    output.extend(
        f"trailer\n<< /Size {len(objects) + 1} /Root {catalog_num} 0 R /Info {info_num} 0 R >>\n"
        f"startxref\n{xref_offset}\n%%EOF\n".encode()
    )
    output_path.write_bytes(bytes(output))
    return output_path
