using Test
using TestSetExtensions
using Logging
using Dates
using DataFrames
using DataStructures
import InfrastructureSystems
import InfrastructureSystems: Deterministic, Probabilistic, Scenarios, Forecast
using PowerSystems
using PowerGraphics
using PowerAnalytics
using PlotlyJS
using PowerSimulations
using StorageSystemsSimulations
using HiGHS
using Weave
using TimeSeries
using HydroPowerSimulations

const PG = PowerGraphics
const IS = InfrastructureSystems
const PSY = PowerSystems
const PSI = PowerSimulations
const PA = PowerAnalytics
const LOG_FILE = "PowerGraphics-test.log"

const BASE_DIR = dirname(dirname(pathof(PowerGraphics)))
const TEST_DIR = joinpath(BASE_DIR, "test")
const TEST_OUTPUTS = joinpath(BASE_DIR, "test", "test_results")
!isdir(TEST_OUTPUTS) && mkdir(TEST_OUTPUTS)
const TEST_RESULT_DIR = joinpath(TEST_OUTPUTS, "results")
!isdir(TEST_RESULT_DIR) && mkdir(TEST_RESULT_DIR)
const TEST_SIM_NAME = "results_sim"

import PowerSystemCaseBuilder
const PSB = PowerSystemCaseBuilder
template_dir = joinpath(BASE_DIR, "report_templates")
const generic_template = joinpath(template_dir, "generic_report_template.jmd")

PA_DIR = string(dirname(dirname(pathof(PowerAnalytics))))
include(joinpath(PA_DIR, "test", "test_data", "results_data.jl"))

LOG_LEVELS = Dict(
    "Debug" => Logging.Debug,
    "Info" => Logging.Info,
    "Warn" => Logging.Warn,
    "Error" => Logging.Error,
)

macro includetests(testarg...)
    if length(testarg) == 0
        tests = []
    elseif length(testarg) == 1
        tests = testarg[1]
    else
        error("@includetests takes zero or one argument")
    end

    quote
        tests = $tests
        rootfile = TEST_DIR
        if length(tests) == 0
            tests = readdir(rootfile)
            tests = filter(
                f ->
                    startswith(f, "test_") && endswith(f, ".jl") && f != basename(rootfile),
                tests,
            )
        else
            tests = map(f -> string(f, ".jl"), tests)
        end
        println()
        for test in tests
            print(splitext(test)[1], ": ")
            include(joinpath(TEST_DIR, test))
            println()
        end
    end
end

function get_logging_level(env_name::String, default)
    level = get(ENV, env_name, default)
    log_level = get(LOG_LEVELS, level, nothing)
    if log_level === nothing
        error("Invalid log level $level: Supported levels: $(values(LOG_LEVELS))")
    end

    return log_level
end

function run_tests()
    console_level = get_logging_level("PS_CONSOLE_LOG_LEVEL", "Error")
    console_logger = ConsoleLogger(stderr, console_level)
    file_level = get_logging_level("PS_LOG_LEVEL", "Info")

    IS.open_file_logger(LOG_FILE, file_level) do file_logger
        levels = (Logging.Info, Logging.Warn, Logging.Error)
        multi_logger =
            IS.MultiLogger([console_logger, file_logger], IS.LogEventTracker(levels))
        global_logger(multi_logger)

        # Testing Topological components of the schema
        @time @testset "Begin PowerGraphics tests" begin
            @includetests ARGS
        end

        @test length(IS.get_log_events(multi_logger.tracker, Logging.Error)) == 0

        @info IS.report_log_summary(multi_logger)
    end
end

logger = global_logger()

try
    run_tests()
finally
    # Guarantee that the global logger is reset.
    @info("removing test files")
    #rm(TEST_OUTPUTS, recursive = true)
    global_logger(logger)
    nothing
end
