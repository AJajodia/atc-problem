using JuMP, GLPK, CSV, DataFrames

sectors_df = DataFrame(CSV.File("mariah_airports.csv"))

airports_df = dropmissing(sectors_df)

airports_list = airports_df.airport

airports = Dict(sectors_df.airport[i] => [sectors_df[i, col] for col in 6:ncol(sectors_df)] for i in 1:nrow(sectors_df))

sectors = Dict(sectors_df.sector[i] => sectors_df.sector_capacity[i] for i in 1:nrow(sectors_df))

sectors_list = sectors_df.sector

timetable_df = DataFrame(CSV.File("mariah_timetable.csv"))

P = DataFrame(CSV.File("flight_paths.csv", header = false))

println(airports)

# Preparing an optimization model
m = Model(GLPK.Optimizer)

F = nrow(timetable_df)
K = sum([!ismissing(sectors_df.airport[i]) for i in 1:nrow(sectors_df)])
J = nrow(sectors_df)
N = [sum([flights[j,i] != "0" for j in 1:nrow(P)]) for i in 1:ncol(P)]


T = [findmin(timetable_df.depart_time): findmax(timetable_df.arrival_time)]

function D(k, t)
    airport = airports_list[k]
    airports[airport][8]
end

function A(k, t)
    airport = airports_list[k]
    return airports[airport][9]
end

function S(j, t)
    sector = sectors_list[j]
    return sectors[sector]


# Declaring variables
@variable(m, w[1:F, 1:24, 1:max(N)])

# Setting the objective
@objective(m, Min, sum(((c[f][1]-c[f][2]) * sum(t*(w[f, t, P[k][1]] - w[f, t-1, P[k][1]]) for t in T)) + c[i][2] for f in 1:F))

# Adding constraints

# airport and sector capacity constraints
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