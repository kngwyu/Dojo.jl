mutable struct Mechanism{T,Nn,Ne,Nb,Ni}
    origin::Origin{T}
    eqconstraints::UnitDict{Base.OneTo{Int64},<:EqualityConstraint{T}}
    bodies::UnitDict{UnitRange{Int64},Body{T}}
    ineqconstraints::UnitDict{UnitRange{Int64},<:InequalityConstraint{T}}

    system::System{Nn}
    residual_entries::Vector{Entry}
    matrix_entries::SparseMatrixCSC{Entry,Int64}
    diagonal_inverses::Vector{Entry}

    Δt::T
    g::T
    μ::T
end

function Mechanism(origin::Origin{T}, bodies::Vector{<:Body{T}}, eqcs::Vector{<:EqualityConstraint{T}}, ineqcs::Vector{<:InequalityConstraint{T}}; 
    spring=0.0, damper=0.0, Δt::T=0.01, g::T=-9.81) where T

    # reset ids
    resetGlobalID()
    order = getGlobalOrder()

    # initialize body states
    for body in bodies
        initialize!(body.state, order)
        if norm(body.m) == 0 || norm(body.J) == 0
            @info "Potentially bad inertial properties detected"
        end
    end

    # dimensions
    Ne = length(eqcs)
    Nb = length(bodies)
    Ni = length(ineqcs)
    Nn = Ne + Nb + Ni

    # nodes
    nodes = [eqcs; bodies; ineqcs]

    # ids
    oldnewid = Dict([node.id=>i for (i,node) in enumerate(nodes)]...)

    for node in nodes
        node.id = oldnewid[node.id]
        if typeof(node) <: Constraint
            node.parentid = get(oldnewid, node.parentid, nothing)
            node.childids = [get(oldnewid, childid, nothing) for childid in node.childids]
        end
    end

    # graph system
    system = create_system(origin, eqcs, bodies, ineqcs)
    residual_entries = deepcopy(system.vector_entries)
    matrix_entries = deepcopy(system.matrix_entries)
    diagonal_inverses = deepcopy(system.diagonal_inverses)

    # springs and dampers 
    eqcs = set_spring_damper!(eqcs, spring, damper)

    # containers for nodes
    eqcs = UnitDict(eqcs)
    bodies = UnitDict((bodies[1].id):(bodies[Nb].id), bodies)
    Ni > 0 ? (ineqcs = UnitDict((ineqcs[1].id):(ineqcs[Ni].id), ineqcs)) : (ineqcs = UnitDict(0:0, ineqcs))

    # complementarity slackness (i.e., contact model "softness")
    μ = 0.0

    Mechanism{T,Nn,Ne,Nb,Ni}(origin, eqcs, bodies, ineqcs, system, residual_entries, matrix_entries, diagonal_inverses, Δt, g, μ)
end

function Mechanism(origin::Origin{T}, bodies::Vector{<:Body{T}}, eqcs::Vector{<:EqualityConstraint{T}}; kwargs...) where T
    return Mechanism(origin, bodies, eqcs, InequalityConstraint{T}[]; kwargs...)
end

function Mechanism(filename::String, floating::Bool=false, T=Float64; kwargs...)
    # parse urdf
    origin, links, joints, loopjoints = parse_urdf(filename, floating, T)

    # create mechanism
    mechanism = Mechanism(origin, links, [joints; loopjoints]; kwargs...)

    # initialize mechanism
    set_parsed_values!(mechanism, loopjoints)

    return mechanism
end

function add_limits(mech::Mechanism, eq::EqualityConstraint; 
    # NOTE: this only works for joints between serial chains
    tra_limits=eq.constraints[1].joint_limits, 
    rot_limits=eq.constraints[1].joint_limits)

    # update translational
    tra = eq.constraints[1]
    T = typeof(tra).parameters[1]
    Nλ = typeof(tra).parameters[2]
    Nb½ = length(tra_limits[1])
    Nb = 2Nb½
    N̄λ = 3 - Nλ
    N = Nλ + 2Nb
    tra_limit = (Translational{T,Nλ,Nb,N,Nb½,N̄λ}(tra.V3, tra.V12, tra.vertices, tra.spring, tra.damper, tra.spring_offset, tra_limits, tra.Fτ, eq.parentid, eq.childids[1]), eq.parentid, eq.childids[1])

    # update rotational
    rot = eq.constraints[2]
    T = typeof(rot).parameters[1]
    Nλ = typeof(rot).parameters[2]
    Nb½ = length(rot_limits[1])
    Nb = 2Nb½
    N̄λ = 3 - Nλ
    N = Nλ + 2Nb
    rot_limit = (Rotational{T,Nλ,Nb,N,Nb½,N̄λ}(rot.V3, rot.V12, rot.qoffset, rot.spring, rot.damper, rot.spring_offset, rot_limits, rot.Fτ, eq.parentid, eq.childids[1]), eq.parentid, eq.childids[1])
    EqualityConstraint((tra_limit, rot_limit); name=eq.name)
end