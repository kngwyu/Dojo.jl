METHODORDER = 1 # This refers to the interpolating spline
getGlobalOrder() = (global METHODORDER; return METHODORDER)

# Convenience functions
@inline getx3(state::State, Δt) = state.x2[1] + state.vsol[2]*Δt
@inline getq3(state::State, Δt) = state.q2[1] * ωbar(state.ϕsol[2],Δt) * Δt / 2

@inline posargs1(state::State) = (state.x1, state.q1)
@inline fullargs1(state::State) = (state.x1, state.v15, state.q1, state.ϕ15)
@inline posargs2(state::State; k=1) = (state.x2[k], state.q2[k])
@inline posargssol(state::State) = (state.xsol[2], state.qsol[2])
@inline fullargssol(state::State) = (state.xsol[2], state.vsol[2], state.qsol[2], state.ϕsol[2])
@inline posargs3(state::State, Δt) = (getx3(state, Δt), getq3(state, Δt))

@inline function derivωbar(ω::SVector{3}, Δt)
    msq = -sqrt(4 / Δt^2 - dot(ω, ω))
    return [ω' / msq; I]
end

@inline function ωbar(ω, Δt)
    return UnitQuaternion(sqrt(4 / Δt^2 - dot(ω, ω)), ω, false)
end

@inline function setForce!(state::State, F, τ)
    state.F2[1] = F
    state.τ2[1] = τ
    return
end

@inline function discretizestate!(body::Body{T}, Δt) where T
    state = body.state
    x1 = state.x1
    q1 = state.q1
    v15 = state.v15
    ϕ15 = state.ϕ15

    state.x2[1] = x1 + v15*Δt
    state.q2[1] = q1 * ωbar(ϕ15,Δt) * Δt / 2

    state.F2[1] = szeros(T,3)
    state.τ2[1] = szeros(T,3)

    return
end

@inline function currentasknot!(body::Body)
    state = body.state

    state.x2[1] = state.x1
    state.q2[1] = state.q1

    return
end

@inline function updatestate!(body::Body{T}, Δt) where T
    state = body.state

    state.x1 = state.xsol[2]
    state.q1 = state.qsol[2]
    state.v15 = state.vsol[2]
    state.ϕ15 = state.ϕsol[2]

    state.x2[1] = state.x2[1] + state.vsol[2]*Δt
    state.q2[1] = state.q2[1] * ωbar(state.ϕsol[2],Δt) * Δt / 2

    state.xsol[2] = state.x2[1]
    state.qsol[2] = state.q2[1]

    state.F2[1] = szeros(T,3)
    state.τ2[1] = szeros(T,3)
    return
end

@inline function setsolution!(body::Body)
    state = body.state
    state.xsol[2] = state.x2[1]
    state.qsol[2] = state.q2[1]
    state.vsol[1] = state.v15
    state.vsol[2] = state.v15
    state.ϕsol[1] = state.ϕ15
    state.ϕsol[2] = state.ϕ15
    return
end

@inline function settempvars!(body::Body{T}, x, v, F, q, ω, τ, d) where T
    state = body.state
    stateold = deepcopy(state)

    state.x1 = x
    state.q1 = q
    state.v15 = v
    state.ϕ15 = ω
    state.F2[1] = F
    state.τ2[1] = τ
    state.d = d

    return stateold
end

function ∂integration(q2::UnitQuaternion{T}, ω2::SVector{3,T}, Δt::T) where {T}
    Δ = Δt * SMatrix{3,3,T,9}(Diagonal(sones(T,3)))
    X = hcat(Δ, szeros(T,3,3))
    Q = hcat(szeros(T,4,3), Lmat(q2)*derivωbar(ω2, Δt)*Δt/2)
    return svcat(X, Q) # 7x6
end