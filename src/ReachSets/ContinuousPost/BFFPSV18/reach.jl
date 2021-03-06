using ..Utils: LDS, CLCDS

using LazySets: CachedMinkowskiSumArray,
                isdisjoint

import LazySets.Approximations: overapproximate

"""
    reach(problem, options)

Interface to reachability algorithms for an LTI system.

### Input

- `problem`   -- initial value problem
- `options`   -- additional options

### Output

A sequence of [`SparseReachSet`](@ref)s.

### Notes

A dictionary with available algorithms is available via
`Reachability.available_algorithms`.

The numeric type of the system's coefficients and the set of initial states
is inferred from the first parameter of the system (resp. lazy set), ie.
`NUM = first(typeof(problem.s).parameters)`.
"""
function reach(problem::Union{IVP{<:CLDS{NUM}, <:LazySet{NUM}},
                              IVP{<:CLCDS{NUM}, <:LazySet{NUM}}},
               options::TwoLayerOptions
              ) where {NUM <: Real}
    # optional matrix conversion
    problem = matrix_conversion(problem, options)

    # list containing the arguments passed to any reachability function
    args = []

    # coefficients matrix
    A = problem.s.A
    push!(args, A)

    # determine analysis mode (sparse/dense) for lazy_expm mode
    if A isa SparseMatrixExp
        push!(args, Val(options[:assume_sparse]))
    end

    n = statedim(problem)
    blocks = options[:blocks]
    partition = convert_partition(options[:partition])
    T = options[:T]
    N = (T == Inf) ? nothing : ceil(Int, T / options[:δ])

    # Cartesian decomposition of the initial set
    if length(partition) == 1 && length(partition[1]) == n &&
            options[:block_options_init] == LinearMap
        info("- Skipping decomposition of X0")
        Xhat0 = LazySet{NUM}[problem.x0]
    else
        info("- Decomposing X0")
        @timing begin
            Xhat0 = array(decompose(problem.x0, options[:partition],
                                    options[:block_options_init]))
        end
    end

    # compute dimensions
    dimensions = compute_dimensions(partition, blocks)

    # determine output function: linear map with the given matrix
    output_function = options[:output_function] != nothing ?
        (x -> options[:output_function] * x) :
        nothing

    # preallocate output vector
    if output_function == nothing
        res_type = SparseReachSet{CartesianProductArray{NUM, LazySet{NUM}}}
    else
        # by default, this algorithm uses box overapproximation
        res_type = SparseReachSet{Hyperrectangle{NUM, Vector{NUM}, Vector{NUM}}}
    end
    res = (N == nothing) ? Vector{res_type}() : Vector{res_type}(undef, N)

    # shortcut if only the initial set is required
    if N == 1
        res[1] = SparseReachSet(CartesianProductArray(Xhat0[blocks]), zero(NUM), options[:δ], dimensions)
        return Flowpipe(res)
    end
    push!(args, Xhat0)

    # inputs
    if !options[:assume_homogeneous] && inputdim(problem) > 0
        U = inputset(problem)
    else
        U = nothing
    end
    push!(args, U)

    # overapproximation function for states
    block_options_iter = options[:block_options_iter]
    if block_options_iter isa AbstractVector ||
            block_options_iter isa Dict{Int, Any}
        # individual overapproximation options per block
        overapproximate_fun = (i, X) -> overapproximate(X, block_options_iter[i])
    else
        # uniform overapproximation options for each block
        overapproximate_fun = (i, X) -> overapproximate(X, block_options_iter)
    end
    push!(args, overapproximate_fun)

    # overapproximate function for inputs
    lazy_inputs_interval = options[:lazy_inputs_interval]
    if lazy_inputs_interval == lazy_inputs_interval_always
        overapproximate_inputs_fun = (k, i, x) -> overapproximate_fun(i, x)
    else
        # first set in a series
        function _f(k, i, x::LinearMap{NUM}) where {NUM}
            @assert k == 1 "a LinearMap is only expected in the first iteration"
            return CachedMinkowskiSumArray(LazySet{NUM}[x])
        end
        # further sets of the series
        function _f(k, i, x::MinkowskiSum{NUM, <:CachedMinkowskiSumArray}) where NUM
            if has_constant_directions(block_options_iter, i)
                # forget sets if we do not use epsilon-close approximation
                forget_sets!(x.X)
            end
            push!(array(x.X), x.Y)
            if lazy_inputs_interval(k)
                # overapproximate lazy set
                y = overapproximate_fun(i, x.X)
                return CachedMinkowskiSumArray(LazySet{NUM}[y])
            end
            return x.X
        end
        function _f(k, i, x)
            # other set types
            if lazy_inputs_interval(k)
                # overapproximate lazy set
                return overapproximate_fun(i, x.X)
            end
            return x
        end
        overapproximate_inputs_fun = _f
    end
    push!(args, overapproximate_inputs_fun)

    # ambient dimension
    push!(args, n)

    # number of computed sets
    push!(args, N)

    # output function
    push!(args, output_function)

    # add mode-specific block(s) argument
    push!(args, blocks)
    push!(args, partition)
    push!(args, dimensions)

    # time step
    push!(args, options[:δ])

    # termination function
    invariant = stateset(problem.s)
    termination = get_termination_function(N, invariant)
    push!(args, termination)

    info("- Computing successors")

    # progress meter
    progress_meter = (N != nothing) ?
        Progress(N, 1, "Computing successors ") :
        nothing
    push!(args, progress_meter)

    # choose algorithm backend
    algorithm = options[:algorithm]
    if algorithm == "explicit"
        algorithm_backend = "explicit_blocks"
    elseif algorithm == "wrap"
        algorithm_backend = "wrap"
    else
        error("Unsupported algorithm: ", algorithm)
    end
    push!(args, res)

    # call the adequate function with the given arguments list
    @timing begin
        index, skip = available_algorithms[algorithm_backend]["func"](args...)
    end

    # shrink result array
    if skip || index < N
        if N != nothing
            info("termination after only $index of $N steps")
        end
        deleteat!(res, (skip ? index : index + 1):length(res))
    end

    # return the result
    return Flowpipe(res)
end

function reach(problem::Union{IVP{<:CLCS{NUM}, <:LazySet{NUM}},
                              IVP{<:CLCCS{NUM}, <:LazySet{NUM}}},
               options::TwoLayerOptions
              ) where {NUM <: Real}
    info("Time discretization...")
    Δ = @timing discretize(problem, options[:δ],
        algorithm=options[:discretization], exp_method=options[:exp_method],
        sih_method=options[:sih_method])
    return reach(Δ, options)
end

function get_termination_function(N::Nothing, invariant::Universe)
    termination_function = (k, set, t0) -> termination_unconditioned()
    warn("no termination condition specified; the reachability analysis will " *
         "not terminate")
    return termination_function
end

function get_termination_function(N::Int, invariant::Universe)
    return (k, set, t0) -> termination_N(N, k, t0)
end

function get_termination_function(N::Nothing, invariant::LazySet)
    return (k, set, t0) -> termination_inv(invariant, set, t0)
end

function get_termination_function(N::Int, invariant::LazySet)
    return (k, set, t0) -> termination_inv_N(N, invariant, k, set, t0)
end

function termination_unconditioned()
    return (false, false)
end

function termination_N(N, k, t0)
    return (k >= N, false)
end

function termination_inv(inv, set, t0)
    if isdisjoint(set, inv)
        return (true, true)
    else
        return (false, false)
    end
end

function termination_inv_N(N, inv, k, set, t0)
    if k >= N
        return (true, false)
    elseif isdisjoint(set, inv)
        return (true, true)
    else
        return (false, false)
    end
end

function overapproximate(X::LazySet, pair::Pair)
    return overapproximate(X, pair[1], pair[2])
end

function overapproximate(X::LazySet, ::Nothing)
    return X
end

function overapproximate(msa::MinkowskiSumArray, ::Nothing)
    return MinkowskiSumArray(copy(array(msa)))
end

function has_constant_directions(block_options::AbstractVector, i::Int)
    return has_constant_directions(block_options[i], i)
end

function has_constant_directions(block_options::Dict{<:UnionAll, <:Real},
                                 i::Int)
    return has_constant_directions(block_options[i], i)
end

function has_constant_directions(block_options::Pair{<:UnionAll, <:Real},
                                 i::Int)
    return has_constant_directions(block_options[2], i)
end

function has_constant_directions(block_options::Real, i::Int)
    return ε == Inf
end

function has_constant_directions(block_options, i::Int)
    return true
end
