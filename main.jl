using JuMP, GLPK, CSV


airports = CSV.read("airports.csv", DataFrame)

# Preparing an optimization model
m = Model(GLPK.Optimizer)



# Declaring variables
@variable()

# Setting the objective
@objective(m, Min, -(1/3)y1) + (2/3)y2

# Adding constraints
@constraint(m, constraint1, y1 + y2 == 1)


# Printing the prepared optimization model
print(m)

# Solving the optimization problem
JuMP.optimize!(m)

# Print the information about the optimum.
println("Objective value: ", objective_value(m))
println("Optimal solutions:")
println("y1 = ", value(y1))
println("y2 = ", value(y2))