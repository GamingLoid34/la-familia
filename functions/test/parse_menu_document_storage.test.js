const test = require("node:test");
const assert = require("node:assert");
const {_test} = require("../parse_menu_document");

test("sniffMimeType känner igen JPEG/PNG/WebP/PDF via magic bytes", () => {
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
  const png = Buffer.from(
      [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00],
  );
  const webp = Buffer.concat([
    Buffer.from("RIFF"),
    Buffer.from([0x00, 0x00, 0x00, 0x00]),
    Buffer.from("WEBP"),
  ]);
  const pdf = Buffer.from("%PDF-1.4\n%âãÏÓ");

  assert.strictEqual(_test.sniffMimeType(jpeg), "image/jpeg");
  assert.strictEqual(_test.sniffMimeType(png), "image/png");
  assert.strictEqual(_test.sniffMimeType(webp), "image/webp");
  assert.strictEqual(_test.sniffMimeType(pdf), "application/pdf");
});

test("sniffMimeType returnerar null för okänt/manipulerat innehåll", () => {
  assert.strictEqual(_test.sniffMimeType(Buffer.from("hej hej")), null);
  assert.strictEqual(_test.sniffMimeType(Buffer.from([])), null);
  // En .exe-fil omdöpt till .jpg känns inte igen som JPEG.
  const exe = Buffer.from([0x4d, 0x5a, 0x90, 0x00]);
  assert.strictEqual(_test.sniffMimeType(exe), null);
});

test("STORAGE_PATH_RE matchar exakt menu_uploads/{familyId}/{filnamn}", () => {
  const cases = [
    ["menu_uploads/fam123/upload_abc.jpg", true, "fam123", "jpg"],
    ["menu_uploads/fam-1_2/bild.PNG", true, "fam-1_2", "PNG"],
    ["menu_uploads/fam123/dok.pdf", true, "fam123", "pdf"],
    ["menu_uploads/fam123/bild.webp", true, "fam123", "webp"],
    // Otillåten filändelse.
    ["menu_uploads/fam123/skript.exe", false],
    // Path traversal i familjesegmentet.
    ["menu_uploads/../secret/x.jpg", false],
    // Path traversal / extra segment i filnamnet.
    ["menu_uploads/fam123/../../x.jpg", false],
    ["menu_uploads/fam123/sub/x.jpg", false],
    // Fel rotmapp.
    ["other_uploads/fam123/x.jpg", false],
    // Saknar filändelse.
    ["menu_uploads/fam123/x", false],
  ];

  for (const [path, shouldMatch, expectedFamilyId, expectedExt] of cases) {
    const match = _test.STORAGE_PATH_RE.exec(path);
    assert.strictEqual(
        match !== null,
        shouldMatch,
        `förväntade match=${shouldMatch} för "${path}"`,
    );
    if (shouldMatch) {
      assert.strictEqual(match[1], expectedFamilyId);
      assert.strictEqual(match[2].toLowerCase(), expectedExt.toLowerCase());
    }
  }
});

test("MIME_BY_EXTENSION täcker alla tillåtna filändelser i regexen", () => {
  for (const ext of ["jpg", "jpeg", "png", "webp", "pdf"]) {
    assert.ok(_test.MIME_BY_EXTENSION[ext], `saknar mime för .${ext}`);
  }
});

test("MAX_STORAGE_FILE_BYTES är 8 MB, samma gräns som base64-vägen", () => {
  assert.strictEqual(_test.MAX_STORAGE_FILE_BYTES, 8 * 1024 * 1024);
});
