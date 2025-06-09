using JuMP
using GLPK

# --- Data Initialization ---
# Define the number of flights, time periods, and sectors
F = 4  # Number of flights
T = 20  # Number of time periods (e.g., hours in a day)
J = 4   # Number of sectors

# Define the cost coefficients for ground and air delays
c_ground = 10  # Ground delay cost per time unit
c_air = 100    # Airborne delay cost per time unit

# Define the sector capacities (maximum number of flights that can be in each sector at any time)
sector_capacity = [4, 4, 4, 4]  # Example capacities for 5 sectors

# Define the flight paths (which sectors each flight traverses)
# Each row represents a flight, and each column represents a time period
# A value of 1 indicates the flight is in that sector at that time
flight_paths = [
    [1, 1, 0, 0, 0],  # Flight 1
    [0, 1, 1, 0, 0],  # Flight 2
    [0, 0, 1, 1, 0],  # Flight 3
    [0, 0, 0, 1, 1],  # Flight 4
    [1, 0, 1, 0, 0],  # Flight 5
    [0, 1, 0, 1, 0],  # Flight 6
    [0, 0, 1, 0, 1],  # Flight 7
    [1, 0, 0, 1, 0],  # Flight 8
    [0, 1, 0, 0, 1],  # Flight 9
    [1, 0, 0, 0, 1]   # Flight 10
]

# --- Model Definition ---
# Create a JuMP model using GLPK as the solver
model = Model(GLPK.Optimizer)

# --- Decision Variables ---
# Define binary decision variables for each flight, time period, and sector
@variable(model, x[1:F, 1:T, 1:J], Bin)

# Define continuous decision variables for the ground delay of each flight
@variable(model, g[1:F, 1:T] >= 0)

# Define continuous decision variables for the airborne delay of each flight
@variable(model, a[1:F, 1:T] >= 0)

# --- Objective Function ---
# The objective is to minimize the total delay costs (ground + airborne)
@objective(model, Min,
    sum(c_ground * g[f, t] + c_air * a[f, t] for f in 1:F, t in 1:T)
)

# --- Constraints ---
# 1. Each flight must be assigned to exactly one sector at each time period
@constraint(model, [f in 1:F, t in 1:T], sum(x[f, t, j] for j in 1:J) == 1)

# 2. The number of flights in each sector at each time period must not exceed the sector capacity
@constraint(model, [t in 1:T, j in 1:J], sum(x[f, t, j] for f in 1:F) <= sector_capacity[j])

# 3. Ground delay is calculated based on the difference between the scheduled and actual departure times
@constraint(model, [f in 1:F, t in 1:T], g[f, t] == max(0, scheduled_departure[f] - t))

# 4. Airborne delay is calculated based on the difference between the scheduled and actual arrival times
@constraint(model, [f in 1:F, t in 1:T], a[f, t] == max(0, scheduled_arrival[f] - t))

# 5. Flight paths must adhere to the predefined sector sequences
@constraint(model, [f in 1:F, t in 1:T, j in 1:J], x[f, t, j] == flight_paths[f, t])

# --- Solve the Model ---
optimize!(model)

# --- Output Results ---
println("Optimal Objective Value: ", objective_value(model))

# Display the assignment of flights to sectors over time
for f in 1:F
    println("Flight ", f, " assignments:")
    for t in 1:T
        for j in 1:J
            if value(x[f, t, j]) > 0.5
                println("  Time ", t, ": Sector ", j)
            end
        end
    end
end
