
# add EAGO#0.3.1
# rm MINLPLib
# rm StaticArrays
# Opposite:
# ]add EAGO#master
# Pkg.add(PackageSpec(path="C:\\Users\\Robert\\OneDrive\\Documents\\Github Repositories\\MINLPLibJuMP.jl"))
# ]add StaticArrays

module EAGO_Differential


    using EAGO, MathOptInterface, LinearAlgebra, DataFrames, CSV

    const IntervalType = Interval{Float64}
    const MOI = MathOptInterface
    const export_path  = "C:/Users/wilhe/Dropbox/Apps/Overleaf/Global optimization with stiff ODE constraints/Plotting_Code_Data"

    import EAGO: build_evaluator!, set_current_node!, set_last_node!,
                 num_state_variables, num_decision_variables,
                 eval_constraint_cc, eval_constraint_cc_grad

    include("C:/Users/Robert/OneDrive/Documents/Github Repositories/EAGODifferential.jl/src/src/calc_ode.jl")

    include("C:/Users/Robert/OneDrive/Documents/Github Repositories/EAGODifferential.jl/src/src/lower_evaluator/lower_evaluator.jl")
    include("C:/Users/Robert/OneDrive/Documents/Github Repositories/EAGODifferential.jl/src/src/upper_evaluator/upper_evaluator.jl")
    include("C:/Users/Robert/OneDrive/Documents/Github Repositories/EAGODifferential.jl/src/src/solve_ode.jl")
    include("C:/Users/Robert/OneDrive/Documents/Github Repositories/EAGODifferential.jl/src/src/data_handling.jl")

    export ImplicitODELowerEvaluator, ImplicitODEUpperEvaluator,
           build_evaluator!, set_current_node!, set_last_node!,
           num_state_variables, num_decision_variables, solve_ode,
           export_path, eval_constraint_cc, eval_constraint_cc_grad

end # module
