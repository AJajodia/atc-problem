using Random
using DataFrames
using CSV

#loading R simulated data
airport_sectors = CSV.read("optimization_project/mariah_airport_sectors.csv", DataFrame) 
timetable = CSV.read("optimization_project/mariah_timetable.csv", DataFrame, 
types=Dict(:depart_airport => String, :arrive_airport => String))

#creating a dictionary for the coordinates of each airport
airport_dict = Dict(row.airport => (row.airport_lat, row.airport_long) 
for row in eachrow(airport_sectors))

#creating a dictionary for the boundaries of each sector
sector_dict = Dict(row.sector => (xmin = row.xmin, xmax = row.xmax, 
ymin = row.ymin, ymax =row.ymax) 
for row in eachrow(airport_sectors))


# create straight line that flight follows, 
#step size = 0.01 (1 mile if 1 unit of lat/long = 100 miles)
function line_path(origin, destination, step_size)
    start_coord = airport_dict[origin]
    end_coord = airport_dict[destination]

    x1 = start_coord[2]
    x2 = end_coord[2]
    y1 = start_coord[1]
    y2 = end_coord[1]

    #how many miles mile
    total_steps = max(
        ceil(Int, abs(x2 - x1) / step_size),
        ceil(Int, abs(y2 - y1) / step_size)
    )

    flight_line = []

    for i in 0:total_steps
        t = i / total_steps
        x = x1 + t * (x2 - x1)
        y = y1 + t * (y2 - y1)
        push!(flight_line, (x, y))
    end

    return flight_line

end

# checker to see if a given point is in a sector (can check along the flight line)
function find_sector(x, y)
    for (sector, bounds) in sector_dict
        if x ≥ bounds.xmin && x ≤ bounds.xmax && y ≥ bounds.ymin && y ≤ bounds.ymax
            return sector
        end
    end
end

function sector_durations(flight_line, airspeed, step_size)
    durations = Dict{Int, Int}()  
    prev_sector = nothing

    for (x, y) in flight_line
        sector = find_sector(x, y)
        if isnothing(sector)
            continue
        end
        if sector == prev_sector
            durations[sector] += 1
        else
            durations[sector] = get(durations, sector, 0) + 1
        end
        prev_sector = sector
    end

    time_per_step = (step_size)*100 / airspeed
    sector_times = Dict(k => round(v * time_per_step, digits=2) for (k, v) in durations)

    return sector_times
end

# find what sectors a flight line crosses
function flight_path(row_number, airspeed, step_size)
    depart_airport = timetable[row_number, 3]
    arrive_airport = timetable[row_number, 5]

    flight_line = line_path(depart_airport, arrive_airport, step_size)
    min_sector_times = sector_durations(flight_line, airspeed, step_size)

    flight_path = Vector{Tuple{Union{String, Int}, Float64}}()
    push!(flight_path, (depart_airport, 0))

    seen_sectors = Set{Int}()

    for (x,y) in flight_line
        s = find_sector(x,y)
        if !(s in seen_sectors)
            push!(flight_path, (s, min_sector_times[s]))
            push!(seen_sectors, s)
        end
    end

    push!(flight_path, (arrive_airport, 0))   
    
    return flight_path
end

airspeed = timetable[1, :airspeed]

all_paths = []
#find longest path
global max_length = 2
for i in 1:nrow(timetable)
    path = flight_path(i, airspeed, 0.01)
    push!(all_paths, path)
    if length(path) > max_length
        global max_length = length(path)
    end
end

# pad remaining paths with Os
padded = [vcat(path, fill((0,0), max_length - length(path))) for path in all_paths]
result = reduce(hcat, padded)

column_names = ["flight_$(i)" for i in 1:20]
padded_df = DataFrame(result, Symbol.(column_names))
CSV.write("flight_paths.csv", padded_df; writeheader = false)