function maximal_to_minimal(mechanism::Mechanism{T,Nn,Ne,Nb,Ni}, z::AbstractVector{Tz}) where {T,Nn,Ne,Nb,Ni,Tz}
	x = []
	for id in mechanism.root_to_leaves
		(id > Ne) && continue # only treat joints
		joint = mechanism.joints[id]
		c = zeros(Tz,0)
		v = zeros(Tz,0)
		ichild = joint.child_id - Ne
		for element in [joint.translational, joint.rotational]
			xb, vb, qb, ϕb = unpack_maximal_state(z, ichild)
			if joint.parent_id != 0
				iparent = joint.parent_id - Ne
				xa, va, qa, ϕa = unpack_maximal_state(z, iparent)
			else
				xa, va, qa, ϕa = current_configuration_velocity(mechanism.origin.state)
			end
			push!(c, minimal_coordinates(element, xa, qa, xb, qb)...)
			push!(v, minimal_velocities(element, xa, va, qa, ϕa, xb, vb, qb, ϕb, mechanism.timestep)...)
		end
		push!(x, [c; v]...)
	end
	x = [x...]
	return x
end

function maximal_to_minimal_jacobian(mechanism::Mechanism{T,Nn,Ne,Nb,Ni}, z::AbstractVector{Tz}) where {T,Nn,Ne,Nb,Ni,Tz}
	J = zeros(minimal_dimension(mechanism), maximal_dimension(mechanism) - Nb)
	timestep = mechanism.timestep
	row_shift = 0
	for id in mechanism.root_to_leaves
		(id > Ne) && continue # only treat joints
		joint = mechanism.joints[id]
		c_shift = 0
		v_shift = control_dimension(joint)
		ichild = joint.child_id - Ne
		for element in [joint.translational, joint.rotational]
			nu_element = control_dimension(element)

			c_idx = row_shift + c_shift .+ (1:nu_element)
			v_idx = row_shift + v_shift .+ (1:nu_element)

			xb, vb, qb, ϕb = unpack_maximal_state(z, ichild)

			xb_idx = collect((ichild-1)*12 .+ (1:3))
			vb_idx = collect((ichild-1)*12 .+ (4:6))
			qb_idx = collect((ichild-1)*12 .+ (7:9))
			ϕb_idx = collect((ichild-1)*12 .+ (10:12))

			if joint.parent_id != 0
				iparent = joint.parent_id - Ne
				xa, va, qa, ϕa = unpack_maximal_state(z, iparent)

				xa_idx = collect((iparent-1)*12 .+ (1:3))
				va_idx = collect((iparent-1)*12 .+ (4:6))
				qa_idx = collect((iparent-1)*12 .+ (7:9))
				ϕa_idx = collect((iparent-1)*12 .+ (10:12))

				J[c_idx, [xa_idx; qa_idx]] = minimal_coordinates_jacobian_configuration(:parent, element, xa, qa, xb, qb)
				J[v_idx, [xa_idx; qa_idx]] = minimal_velocities_jacobian_configuration(:parent, element, xa, va, qa, ϕa, xb, vb, qb, ϕb, timestep)
				J[v_idx, [va_idx; ϕa_idx]] = minimal_velocities_jacobian_velocity(:parent, element, xa, va, qa, ϕa, xb, vb, qb, ϕb, timestep)
			else
				xa, va, qa, ϕa = current_configuration_velocity(mechanism.origin.state)
			end

			J[c_idx, [xb_idx; qb_idx]] = minimal_coordinates_jacobian_configuration(:child, element, xa, qa, xb, qb)
			J[v_idx, [xb_idx; qb_idx]] = minimal_velocities_jacobian_configuration(:child, element, xa, va, qa, ϕa, xb, vb, qb, ϕb, timestep)
			J[v_idx, [vb_idx; ϕb_idx]] = minimal_velocities_jacobian_velocity(:child, element, xa, va, qa, ϕa, xb, vb, qb, ϕb, timestep)

			c_shift += nu_element
			v_shift += nu_element
		end
		row_shift += 2 * control_dimension(joint)
	end
	return J
end

function get_maximal_gradients(mechanism::Mechanism{T,Nn,Ne,Nb,Ni}) where {T,Nn,Ne,Nb,Ni}
	timestep = mechanism.timestep
	nu = control_dimension(mechanism)

	for entry in mechanism.data_matrix.nzval # reset matrix
		entry.value .= 0.0
	end
	jacobian_data!(mechanism.data_matrix, mechanism)
	nodes = [mechanism.joints; mechanism.bodies; mechanism.contacts]
	dimrow = length.(nodes)
	dimcol = data_dim.(nodes)
	index_row = [1+sum(dimrow[1:i-1]):sum(dimrow[1:i]) for i in 1:length(dimrow)]
	index_col = [1+sum(dimcol[1:i-1]):sum(dimcol[1:i]) for i in 1:length(dimcol)]

	index_state = [index_col[body.id][[14:16; 8:10; 17:19; 11:13]] for body in mechanism.bodies] # ∂ x2 v15 q2 ϕ15
	index_control = [index_col[joint.id][1:control_dimension(joint)] for joint in mechanism.joints] # ∂ u

	datamat = full_matrix(mechanism.data_matrix, dimrow, dimcol)
	solmat = full_matrix(mechanism.system)

	# data Jacobian
	data_jacobian = solmat \ datamat #TODO: use pre-factorization

	# Jacobian
	jacobian_state = zeros(12Nb,12Nb)
	jacobian_control = zeros(12Nb,nu)
	for (i, body) in enumerate(mechanism.bodies)
		id = body.id
		# Fill in gradients of v25, ϕ25
		jacobian_state[12*(i-1) .+ [4:6; 10:12],:] += data_jacobian[index_row[id], vcat(index_state...)]
		jacobian_control[12*(i-1) .+ [4:6; 10:12],:] += data_jacobian[index_row[id], vcat(index_control...)]

		# Fill in gradients of x3, q3
		q2 = body.state.q2[1]
		ϕ25 = body.state.ϕsol[2]
		q3 = next_orientation(q2, ϕ25, timestep)
		jacobian_state[12*(i-1) .+ (1:3), :] += linear_integrator_jacobian_velocity(timestep) * data_jacobian[index_row[id][1:3], vcat(index_state...)]
		jacobian_state[12*(i-1) .+ (1:3), 12*(i-1) .+ (1:3)] += linear_integrator_jacobian_position()
		jacobian_state[12*(i-1) .+ (7:9), :] += LVᵀmat(q3)' * rotational_integrator_jacobian_velocity(q2, ϕ25, timestep) * data_jacobian[index_row[id][4:6], vcat(index_state...)]
		jacobian_state[12*(i-1) .+ (7:9), 12*(i-1) .+ (7:9)] += LVᵀmat(q3)' * rotational_integrator_jacobian_orientation(q2, ϕ25, timestep, attjac=true)

		jacobian_control[12*(i-1) .+ (1:3),:] += linear_integrator_jacobian_velocity(timestep) * data_jacobian[index_row[id][1:3], vcat(index_control...)]
		jacobian_control[12*(i-1) .+ (7:9),:] += LVᵀmat(q3)' * rotational_integrator_jacobian_velocity(q2, ϕ25, timestep) * data_jacobian[index_row[id][4:6], vcat(index_control...)]
	end
	
	return jacobian_state, jacobian_control
end

function get_maximal_gradients!(mechanism::Mechanism{T,Nn,Ne,Nb,Ni}, z::AbstractVector{T}, u::AbstractVector{T};
    opts=SolverOptions()) where {T,Nn,Ne,Nb,Ni}

    step!(mechanism, z, u, opts=opts)
    jacobian_state, jacobian_control = get_maximal_gradients(mechanism)

    return jacobian_state, jacobian_control
end

function get_maximal_state(mechanism::Mechanism{T,Nn,Ne,Nb,Ni}) where {T,Nn,Ne,Nb,Ni}
	z = zeros(T, 13Nb)
	for (i, body) in enumerate(mechanism.bodies)
		x2 = body.state.x2[1]
		v15 = body.state.v15
		q2 = body.state.q2[1]
		ϕ15 = body.state.ϕ15
		set_maximal_state!(z, x2, v15, q2, ϕ15, i)
	end
	return z
end

function unpack_maximal_state(z::AbstractVector, i::Int)
	zi = z[(i-1)*13 .+ (1:13)]
	x2 = zi[SUnitRange(1,3)]
	v15 = zi[SUnitRange(4,6)]
	q2 = UnitQuaternion(zi[7:10]..., false)
	ϕ15 = zi[SUnitRange(11,13)]
	return x2, v15, q2, ϕ15
end

function set_maximal_state!(z::AbstractVector, x2::AbstractVector, v15::AbstractVector,
		q2::UnitQuaternion, ϕ15::AbstractVector, i::Int)
	z[(i-1)*13 .+ (1:3)] = x2
	z[(i-1)*13 .+ (4:6)] = v15
	z[(i-1)*13 .+ (7:10)] = vector(q2)
	z[(i-1)*13 .+ (11:13)] = ϕ15
	return nothing
end
