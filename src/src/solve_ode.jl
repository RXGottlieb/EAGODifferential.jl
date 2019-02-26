function interval_preprocess_ode!(x::EAGO.Optimizer, y::EAGO.NodeBB)

    Eflag = false
    Iflag = false
    eDflag = false
    evaluator = x.nlp_data.evaluator
    nx = evaluator.nx
    np = evaluator.np
    nt = evaluator.nt

    set_current_node!(evaluator, y)

    g = zeros(evaluator.ng)
    MOI.eval_constraint(evaluator, g, y)
    Eflag = evaluator.exclusion_flag
    if ~Eflag
        EFlag = any(i-> (i > 0), g)
    end

    x.current_preprocess_info.feasibility = ~Eflag
    if ~Eflag
        if nx == 1
            y.lower_variable_bounds[1:(nt-1)] = lo.(evaluator.state_relax_1)
            y.upper_variable_bounds[1:(nt-1)] = hi.(evaluator.state_relax_1)
        else
            for i in 1:(nt-1)
                y.lower_variable_bounds[(1+(i-1)*nx):(i*nx)] = lo.(evaluator.state_relax_n[:,i])
                y.upper_variable_bounds[(1+(i-1)*nx):(i*nx)] = hi.(evaluator.state_relax_n[:,i])
            end
        end
    end
end

function create_mid_node(y::NodeBB, nx::Int, np::Int, nt::Int)

    lower_variable_bounds = y.lower_variable_bounds
    upper_variable_bounds = y.upper_variable_bounds

    P_interval = EAGO.IntervalType.(lower_variable_bounds[(nx*(nt-1)+1):(nx*(nt-1)+np)]
                                    upper_variable_bounds[(nx*(nt-1)+1):(nx*(nt-1)+np)])
    P_mid_interval = EAGO.IntervalType.(mid.(P_interval))

    lower_variable_bounds[(nx*(nt-1)+1):(nx*(nt-1)+np)] = lo.(P_mid_interval[:])
    upper_variable_bounds[(nx*(nt-1)+1):(nx*(nt-1)+np)] = hi.(P_mid_interval[:])

    ymid = EAGO.NodeBB(lower_variable_bounds, upper_variable_bounds,
                       y.lower_bound, y.upper_bound, y.depth, y.last_branch,
                       y.branch_direction)

    return ymid
end

function midpoint_upper_bnd_ode!(x::EAGO.Optimizer, y::NodeBB)
    if EAGO.is_integer_feasible(x) #&& mod(x.CurrentIterationCount,x.UpperBoundingInterval) == 1

        evaluator = x.nlp_data.evaluator
        nx = evaluator.nx
        np = evaluator.np
        nt = evaluator.nt

        node_ymid = create_mid_node(y, nx, np, nt)
        set_current_node!(evaluator, node_ymid)
        EAGO.set_to_mid!(x.current_upper_info.solution, y)
        Eflag = evaluator.exclusion_flag
        if evaluator.ng > 0
            g = zeros(evaluator.ng)
            MOI.eval_constraint(evaluator, g, x.current_upper_info.solution)
            result_status = any(i-> (i > 0), g) ? MOI.INFEASIBLE_POINT : MOI.FEASIBLE_POINT
            if (result_status == MOI.FEASIBLE_POINT)
                result_status = evaluator.exclusion_flag ? MOI.INFEASIBLE_POINT : MOI.FEASIBLE_POINT
            end
        else
            result_status = MOI.FEASIBLE_POINT
        end
        if (result_status == MOI.FEASIBLE_POINT)
            x.current_upper_info.feasibility = true
            val = MOI.eval_objective(evaluator, x.current_upper_info.solution)
            x.current_upper_info.value = val
        else
            x.current_upper_info.feasibility = false
            x.current_upper_info.value = Inf
        end
    else
        x.current_upper_info.feasibility = false
        x.current_upper_info.value = Inf
    end
end

# Modifies functions post initial relaxation to use appropriate nlp evaluator
function ode_mod!(opt::Optimizer, args)

    ImpLowerEval = args[1]
    ImpUpperEval = args[2]
    lower_bnds = args[3]
    upper_bnds = args[4]

    opt.preprocess! = interval_preprocess_ode!
    opt.relax_function! = implicit_relax_model!
    opt.upper_problem! = midpoint_upper_bnd_ode!

    # load lower nlp data block
    lower_eval_block = MOI.NLPBlockData(lower_bnds, ImpLowerEval, true)
    opt.working_evaluator_block = deepcopy(lower_eval_block)
    if MOI.supports(opt.initial_relaxed_optimizer, MOI.NLPBlock())
        opt.initial_relaxed_optimizer.nlp_data = deepcopy(lower_eval_block)
        opt.working_relaxed_optimizer.nlp_data = deepcopy(lower_eval_block)
    end

    # load upper nlp data block
    upper_eval_block = MOI.NLPBlockData(upper_bnds, ImpUpperEval, true)
    # if using the midpoint evaluator don't setup upper optimizers &
    if alt_upper_flag
        opt.upper_problem! = alt_upper
    else
        if MOI.supports(opt.initial_relaxed_optimizer, MOI.NLPBlock())
            opt.initial_upper_optimizer.nlp_data = deepcopy(upper_eval_block)
            opt.working_upper_optimizer.nlp_data = deepcopy(upper_eval_block)
        end
    end
    opt.nlp_data = upper_eval_block
end

"""
    solve_ode

Solves the optimization problem `min_{x,p} f(x,p,t)` with respect to_indices
`dx/dt = h(x,p,t)` on `x in X` and `p in P`.
"""
function solve_ode(f, h, hj, g, x0, xL, xU, pL, pU, t_start, t_end, nt, s, method, opt)

    # get dimensions & check for consistency
    @assert length(pl) == length(pu)
    @assert length(xl) == length(xu)
    np = length(pl); nx = length(xl);

    if (g_func == nothing)
        ng = 0
    else
        ng = length(g_func(ones(nx),ones(np),ones(nt)))
    end

    # sets most routines to default (expect bisection)
    EAGO.set_to_default!(opt)
    opt.bisection_function = EAGO.implicit_bisection

    # Add variables
    var_EAGO = MOI.add_variables(opt, nx*(nt-1)+np)
    count = 1
    for i in 1:(nt-1)
        for j in 1:nx
            MOI.add_constraint(opt, var_EAGO[count], MOI.GreaterThan(xL[j]))
            MOI.add_constraint(opt, var_EAGO[count], MOI.LessThan(xL[j]))
            count += 1
        end
    end

    for i in 1:np
        MOI.add_constraint(opt, var_EAGO[i+nx*(nt-1)], MOI.GreaterThan(pL[i]))
        MOI.add_constraint(opt, var_EAGO[i+nx*(nt-1)], MOI.LessThan(pU[i]))
    end

    # Specify number of state variables
    opt.state_variables = nx*(nt-1)
    opt.upper_has_node = true

    # creates the appropriate lower evaluator
    lower = ImplicitLowerEvaluator{np}()
    EAGO_Differential.build_evaluator!(lower, f, h, np, nx, nt, s, method,
                                              t_start, t_end, pL, pU, xL, xU,
                                              x0; hj = hj, g = g)
    upper = ImplicitLowerEvaluator{np}()
    EAGO_Differential.build_evaluator!(upper, f, h, np, nx, nt, s, t_start,
                                              t_end, method, pL, pU, xL, xU,
                                              x0; hj = hj, g = g)

    # Add nlp data blocks ("SHOULD" BE THE LAST THING TO DO)
    bnd_pair = MOI.NLPBoundsPair(-Inf,0.0)
    lower_bnds = [bnd_pair for i=1:ng]
    upper_bnds = [bnd_pair for i=1:ng]

    # Set the objective sense
    MOI.set(opt, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    custom_mod_args = (lower, upper, lower_bnds, upper_bnds)
    MOI.optimize!(opt, custom_mod! = ode_mod!, custom_mod_args = custom_mod_args)
    return var_EAGO, opt
end
