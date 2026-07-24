# Gallery card source of truth: (title, image basename without .png, code, @ref target).
# Shared by write_gallery_page.jl and generate_gallery.jl.

const GALLERY_ENTRIES = [
    (
        title = "Demand stack",
        image = "demand_stack",
        code = "plot_demand(...; aggregate=\"System\", stack=true)",
        ref = "plot_demand",
    ),
    (
        title = "Fuel",
        image = "fuel",
        code = "plot_fuel(res)",
        ref = "plot_fuel",
    ),
    (
        title = "Lines",
        image = "powerdata_line",
        code = "plot_powerdata(gen; label_fn=label_component)",
        ref = "plot_powerdata",
    ),
    (
        title = "Stack",
        image = "powerdata_stack",
        code = "plot_powerdata(gen; stack=true, label_fn=label_component)",
        ref = "plot_powerdata",
    ),
    (
        title = "Stair",
        image = "powerdata_stair",
        code = "plot_powerdata(gen; stair=true, label_fn=label_component)",
        ref = "plot_powerdata",
    ),
    (
        title = "Bar",
        image = "powerdata_bar",
        code = "plot_powerdata(gen; bar=true, label_fn=label_component)",
        ref = "plot_powerdata",
    ),
    (
        title = "Stacked bar",
        image = "powerdata_bar_stack",
        code = "plot_powerdata(gen; bar=true, stack=true, label_fn=label_component)",
        ref = "plot_powerdata",
    ),
    (
        title = "DataFrame",
        image = "dataframe",
        code = "plot_dataframe(df, time)",
        ref = "plot_dataframe",
    ),
]
