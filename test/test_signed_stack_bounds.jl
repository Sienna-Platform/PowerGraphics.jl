@testset "sign-aware stacked bounds" begin
    # Per-series classification (by net sign, matching PlotlyLight sign_group):
    # positive-type series stack up from 0, negative-type (storage charging)
    # stack down from 0. col1 sum>0, col2 sum<0, col3 sum>0.
    data = [10.0 -3.0 5.0;
        8.0 -2.0 0.0]
    lower, upper = PG._signed_stack_bounds(data)

    @test lower == [0.0 -3.0 10.0; 0.0 -2.0 8.0]
    @test upper == [10.0 0.0 15.0; 8.0 0.0 8.0]

    # Negative (charging) band entirely <= 0.
    @test all(upper[:, 2] .<= 0)
    @test all(lower[:, 2] .< 0)

    # Positive stack top excludes charging (10 + 5).
    @test upper[1, 3] == 15.0

    # A positive series that drops to 0 stays anchored at its stack position
    # (on top of the series below it), NOT at 0 — no whitespace hole / slash
    # line at the zero-crossing. col2 sum>0 -> positive-type.
    d3 = [2.0 3.0;
        2.0 0.0]
    lo3, up3 = PG._signed_stack_bounds(d3)
    @test lo3[:, 2] == [2.0, 2.0]          # zero point sits on series 1, not 0
    @test up3[:, 2] == [5.0, 2.0]          # zero-width band in place at t=2

    # A mostly-zero charging series stays at/below 0, never at the positive top.
    d2 = [5.0 0.0;
        5.0 -3.0]
    lo2, up2 = PG._signed_stack_bounds(d2)
    @test up2[:, 2] == [0.0, 0.0]
    @test lo2[:, 2] == [0.0, -3.0]

    # All-positive input behaves like a plain cumulative stack.
    pos = [1.0 2.0 3.0]
    lo, up = PG._signed_stack_bounds(pos)
    @test lo == [0.0 1.0 3.0]
    @test up == [1.0 3.0 6.0]
end
