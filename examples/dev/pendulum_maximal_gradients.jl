################################################################################
# Development
################################################################################
using Dojo

# Open visualizer
vis = Visualizer()
open(vis)

# Mechanism
mech = get_mechanism(:npendulum, timestep = 0.01, gravity = -9.81, Nb=1)#, spring = 100.0, damper = 5.0)
mech.origin.id
mech.bodies[1].id
mech.joints[1].id
mech.joints[1].parent_id
mech.joints[1].child_ids


Random.seed!(100)
ϕ1 = 0.3π
initialize!(mech, :npendulum, ϕ1 = ϕ1)

# origin = Dojo.Origin{Float64}()
# origin.id
# getGlobalID()
# resetGlobalID()
# origin.id

mech = get_mechanism(:sphere, timestep = 0.01, gravity = -9.81)
initialize!(mech, :sphere)

storage = simulate!(mech, 1.0, record = true, verbose = false)
visualize(mech, storage, vis = vis)

## Maximal gradients 
maximal_dimension(mech)
minimal_dimension(mech)
z = get_maximal_state(mech)
u = zeros(control_dimension(mech))
maximal_to_minimal(mech, z)

M_fd = maximal_to_minimal_jacobian(mech, z)
M_a = maximal_to_minimal_jacobian_analytical(mech, z)

@assert size(M_fd) == size(M_a)
norm(M_fd - M_a, Inf)

################################################################################
# Differentiation
################################################################################

include(joinpath(module_dir(), "examples", "diff_tools.jl"))
# Set data
data = get_data(mech)
set_data!(mech, data)
sol = get_solution(mech)
Nb = length(collect(mech.bodies))
attjac = attitude_jacobian(data, Nb)

data = get_data(mech)
v15 = data[4:6]
sol = get_solution(mech)
v25 = sol[6:8]
norm(v15 - v25)

# IFT
set_entries!(mech)
datamat = full_data_matrix(mech, attjac = true)
datamat1 = full_data_matrix(mech, attjac = false)
datamat2 = full_data_matrix(mech, attjac = false) * attjac
plot(Gray.(attjac))

solmat = full_matrix(mech.system)
sensi = - (solmat \ datamat)
@show cond(solmat)
@show rank(solmat)
@show norm(full_vector(mech.system), Inf)

# finite diff
fd_datamat = finitediff_data_matrix(mech, data, sol) * attjac
fd_datamat1 = finitediff_data_matrix(mech, data, sol)
@test norm(fd_datamat + datamat, Inf) < 1e-7
@test norm(fd_datamat1 + datamat1, Inf) < 1e-7
@test norm(fd_datamat + datamat2, Inf) < 1e-7
plot(Gray.(abs.(datamat)))
plot(Gray.(abs.(fd_datamat)))


fd_solmat = finitediff_sol_matrix(mech, data, sol)
@test norm(fd_solmat + solmat, Inf) < 1e-7
plot(Gray.(abs.(fd_solmat)))
plot(Gray.(abs.(solmat)))


fd_sensi = finitediff_sensitivity(mech, data) * attjac
@test norm(fd_sensi - sensi) / norm(fd_sensi) < 5e-3
plot(Gray.(sensi))
plot(Gray.(fd_sensi))
norm(fd_sensi - sensi, Inf)
norm(fd_sensi, Inf)

###############################################################################
# plot
###############################################################################

plot(hcat(Vector.(storage.x[1])...)')
plot(hcat([[q.w, q.x, q.y, q.z] for q in storage.q[1]]...)')
plot(hcat(Vector.(storage.v[1])...)')
plot(hcat(Vector.(storage.ω[1])...)')


sdf = get_sdf(mech, storage)
plot(hcat(sdf[1]...)', ylims = (-0.01,0.01))
plot(hcat(sdf[2]...)', ylims = (-0.01,0.01))
plot(hcat(sdf[3]...)', ylims = (-0.01,0.01))
plot(hcat(sdf[4]...)', ylims = (-0.01,0.01))
plot(hcat(sdf[5]...)')
plot(hcat(sdf[6]...)')
plot(hcat(sdf[7]...)')
plot(hcat(sdf[8]...)')