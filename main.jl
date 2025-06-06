using JuMP, GLPK, CSV


airports = CSV.read("airports.csv", DataFrame)

# Preparing an optimization model
m = Model(GLPK.Optimizer)

F = 20
K = 4
J = 10

N = [1:20]

T_max = 24
T_min 

T = [1:20]

P = [[1, 2, 3],[4, 5, 6]]

# Declaring variables
@variable(m, w[1:F, 1:24, 1:max(N)])

# Setting the objective
@objective(m, Min, sum(((c[f][1]-c[f][2]) * sum(t*(w[f, t, P[k][1]] - w[f, t-1, P[k][1]]) for t in T)) + c[i][2] for f in 1:F))

# Adding constraints

# aiport and sector capacity constraints
for k in 1:K, t in 1:T
    @constraint(m, sum((w[f, t, 1] - w[f, t-1, 1]) for f in 1:F if P[k][1] == k) <= D[t][k])
    @constraint(m, sum((w[f, t, 1] - w[f, t-1, 1]) for f in 1:F if P[k][1] == k) <= A[t][k])
    @constraint(m, )
end

# connectivity constraints

# Printing the prepared optimization model
print(m)

# Solving the optimization problem
JuMP.optimize!(m)

# Print the information about the optimum.
println("Objective value: ", objective_value(m))
println("Optimal solutions:")
println("y1 = ", value(y1))
println("y2 = ", value(y2))