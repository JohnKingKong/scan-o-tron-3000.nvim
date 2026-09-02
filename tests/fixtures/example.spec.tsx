const noNames = () => [];
const STORAGE_KEY = "x";

describe("Widget", () => {
  it("renders nothing when there is no data", () => {
    const { container } = render(
      <Widget
        data={undefined}
        current={undefined}
        getNames={noNames}
        onAction={jest.fn()}
      />,
    );

    expect(container).toBeEmptyDOMElement();
  });

  describe("themed", () => {
    afterEach(() => {
      localStorage.removeItem(STORAGE_KEY);
    });

    it("applies the selected theme", () => {
      const onAction = jest.fn();
      render(
        <ThemeProvider>
          <Widget
            data={{ "1a2b3c": 1 }}
            current={undefined}
            getNames={noNames}
            onAction={onAction}
          />
        </ThemeProvider>,
      );

      expect(onAction).toHaveBeenCalledWith(`1a2b3c-x`);
    });
  });
});
