# Imports
using JuMP, GLPK, CSV, DataFrames

# --- Data preprocessing ---

sectors_df = DataFrame(CSV.File("mariah_airport_sectors.csv"))
airports_df = filter(row -> all(x -> x != "NA", row), sectors_df)

airports_list = string.(airports_df.airport)
sectors_list = string.(sectors_df.sector)

# Dictionary of airport data
airports = Dict(string(sectors_df.airport[i]) => [sectors_df[i, col] for col in 6:ncol(sectors_df)] for i in 1:nrow(sectors_df))
sector_capacity = Dict(string(sectors_df.sector[i]) => sectors_df.sector_capacity[i] for i in 1:nrow(sectors_df))

# Timetable and lookup
timetable_df = DataFrame(CSV.File("mariah_timetable.csv"))
sector_lookup = Dict(sectors_list[i] => i for i in 1:nrow(sectors_df))
airport_lookup = Dict(sectors_df.airport[i] => i for i in 1:nrow(sectors_df))

l = DataFrame(CSV.File("min_times_anu.csv", header = false))
start_df = DataFrame(CSV.File("flight_min_times_anu.csv", header = false))
buffer_time = 4
P = DataFrame(CSV.File("flight_paths_anu.csv", header = false))

#print(vcat(timetable_df, timetable_df))
l2 = copy(l)
rename!(l2, Symbol.(string.("col", 1:ncol(l))))  # Rename columns in l2 to avoid collision
print(hcat(l, l2))