describe("outer", () => {
  it("does the first thing", () => {
    expect(1).toBe(1);
  });

  describe("inner", () => {
    it("does the second thing", () => {
      expect(2).toBe(2);
    });
  });
});

test("a bare test call", () => {
  expect(3).toBe(3);
});
