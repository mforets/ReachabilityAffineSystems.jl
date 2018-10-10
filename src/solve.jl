export solve

function default_operator(system::InitialValueProblem{<:S}) where
        {S<:Union{AbstractContinuousSystem, AbstractDiscreteSystem}}
    if S <: LinearContinuousSystem ||
            S <: LinearControlContinuousSystem ||
            S <: ConstrainedLinearContinuousSystem ||
            S <: ConstrainedLinearControlContinuousSystem ||
            S <: LinearDiscreteSystem ||
            S <: LinearControlDiscreteSystem ||
            S <: ConstrainedLinearDiscreteSystem ||
            S <: ConstrainedLinearControlDiscreteSystem
        op = BFFPSV18()
    else
        error("no default reachability algorithm available for system of " *
              "type $(typeof(system))")
    end
    return op
end

function default_operator(system::InitialValueProblem{<:HybridSystem})
    opC = BFFPSV18()
    opD = TextbookDiscretePost()
    return opC, opD
end

"""
    solve(system, options)  or  solve(system, :key1 => val1, [...], keyK => valK)

Solves a reachability problem s.t. the given options.
If some options are not defined, we may fall back to default values.

### Input

- `system`    -- a (discrete or continuoues) system specification
- `options`   -- algorithm options for solving the problem
- `algorithm` -- (optional, default: dispatched on the system's type) the
                 reachability algorithm for the computation

### Output

A solution object whose content depends on the input options.

### Notes

To see all available input options, see
`keys(Reachability.available_keywords.dict)`.
"""
function solve(system::InitialValueProblem,
               options::Options;
               op::PostOperator=default_operator(system))
    solve!(system, Options(copy(options.dict)), op=op)
end

solve(system::AbstractSystem, options::Pair{Symbol,<:Any}...) =
    solve(system, Options(Dict{Symbol,Any}(options)))

function solve!(system::InitialValueProblem{<:SYS},
                options_input::Options;
                op::PostOperator=default_operator(system)
               )::AbstractSolution where {SYS<:Union{AbstractContinuousSystem,
                                                     AbstractDiscreteSystem}}
    options = init(op, system, options_input)

    # coordinate transformation
    options[:transformation_matrix] = nothing
    if options[:coordinate_transformation] != ""
        info("Transformation...")
        tic()
        (system, transformation_matrix) =
            transform(system, options[:coordinate_transformation])
        tocc()
        options[:transformation_matrix] = transformation_matrix
    end

    post(op, system, options)
end

"""
    solve(system::InitialValueProblem{<:HybridSystem},
          options::Options)::AbstractSolution

Interface to reachability algorithms for a hybrid system PWA dynamics.

### Input

- `system`  -- hybrid system
- `options` -- options for solving the problem
"""
function solve(system::InitialValueProblem{<:HybridSystem, <:LazySet{N}},
               options::Options)::AbstractSolution where {N}
    opC, opD = default_operator(system)
    return solve(system, options, opC, opD)
end

function solve(system::InitialValueProblem{<:HybridSystem, <:LazySet{N}},
               options_input::Options,
               opC::ContinuousPost,
               opD::DiscretePost
              )::AbstractSolution where {N}
    HS = system.s
    X0 = system.x0
    delete_N = !haskey(options_input.dict, :N)
    options = init(opD, HS, options_input)
    time_horizon = options[:T]
    max_jumps = options[:max_jumps]

    #TODO get initial location. For now we assume that it is the first location
    # waiting_list entries:
    # - (discrete) location
    # - (set of) continuous-time reach sets
    # - number of previous jumps
    inits = length(options[:init]) > 0 ? options[:init] : [(n, X0) for n in states(HS)]

    waiting_list = []
    for (modeId, x0) in inits
        mode = HS.modes[modeId]
        source_invariant = mode.X

        if source_invariant isa HalfSpace
            # TODO temporary conversion to HPolytope
            source_invariant = HPolytope([source_invariant])
        else
            @assert source_invariant isa HPolytope
        end

        loc_x0sets = intersection(source_invariant, x0)

        if !isempty(loc_x0sets)
            push!(waiting_list,(modeId, ReachSet{LazySet{N}, N}(loc_x0sets, zero(N), zero(N)), 0))
        end
    end


    # passed_list maps the (discrete) location to the (set of) continuous-time
    # reach sets
    passed_list = options[:fixpoint_check] ?
        Vector{Vector{ReachSet{LazySet{N}, N}}}(nstates(HS)) :
        nothing

    Rsets = Vector{ReachSet{LazySet{N}, N}}()
    while (!isempty(waiting_list))
        loc_id, X0, jumps = pop!(waiting_list)
        loc = HS.modes[loc_id]

        # compute reach tube
        options_copy = Options(copy(options.dict))
        options_copy.dict[:T] = time_horizon - X0.t_start
        options_copy.dict[:project_reachset] = false
        delete!(options_copy.dict, :inout_map)
        if delete_N # TODO add more conditions or fix option clashes in general
            delete!(options_copy.dict, :N)
        end
        if haskey(options_copy.dict, :block_types) &&
                options_copy.dict[:block_types] == nothing
            delete!(options_copy.dict, :block_types)
        end
        if haskey(options_copy.dict, :blocks)
            delete!(options_copy.dict, :blocks)
        end
        reach_tube = solve(ContinuousSystem(loc.A, X0.X, loc.U),
                           options_copy,
                           op=opC)

        tube⋂inv = tube⋂inv!(opD, reach_tube.Xk, loc.X, Rsets,
                             [X0.t_start, X0.t_end])

        if jumps == max_jumps
            continue
        end

        post(opD, system, waiting_list, passed_list, loc_id, tube⋂inv, jumps)
    end

    # Projection
    if options[:project_reachset] || options[:projection_matrix] != nothing
        info("Projection...")
        tic()
        RsetsProj = project(Rsets, options)
        tocc()
    else
        RsetsProj = Rsets
    end
    return ReachSolution(RsetsProj, options)
end
