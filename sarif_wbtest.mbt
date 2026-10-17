///|
test "SARIF coordinate boundary cases refuse invalid offsets and retain unknown positions" {
  assert_true(sarif_region("x", -1) is None)
  assert_eq(
    sarif_region("", 0).unwrap(),
    Json::object({ "startLine": 1, "startColumn": 1, "endColumn": 1 }),
  )
  assert_eq(
    sarif_region("\uFEFF😀", 3).unwrap(),
    Json::object({ "startLine": 1, "startColumn": 3, "endColumn": 3 }),
  )
  assert_true(sarif_region("a\r\nb", 1) is None)
  assert_true(sarif_region("a\r\nb", 2) is None)
  assert_eq(
    sarif_region("a\r\nb", 3).unwrap(),
    Json::object({ "startLine": 2, "startColumn": 1, "endColumn": 1 }),
  )
  let refused = try {
    ignore(sarif_region("", 1))
    false
  } catch {
    Refused(d) => d.code == "SarifPosition"
  }
  assert_true(refused)
  let value = Json::object({
    "quote": Json("\"\n\t😀"),
    "a": [true, false, null, 1],
  })
  assert_eq(@json.parse(sarif_json(value)), value)
}
