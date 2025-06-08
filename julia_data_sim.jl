using Random
using DataFrames
using CSV

#loading R simulated data
airport_sectors = CSV.read("mariah_airport_sectors.csv", DataFrame) 
timetable = CSV.read("mariah_timetable.csv", DataFrame, 
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

function sector_durations(flight_line, airspeed)
    sector_entries = Dict{Any, Tuple{Float64, Float64}}()
    sector_exits = Dict{Any, Tuple{Float64, Float64}}()

    prev_sector = nothing

    for (x, y) in flight_line
        sector = find_sector(x, y)
        if isnothing(sector)
            continue
        end

        if !haskey(sector_entries, sector)
            sector_entries[sector] = (x, y)
        end

        sector_exits[sector] = (x, y)

        prev_sector = sector
    end

    sector_times = Dict{Any, Float64}()
    for sector in keys(sector_entries)
        entry = sector_entries[sector]
        exit = sector_exits[sector]
        dist = sqrt((100*exit[1] - 100*entry[1])^2 + (100*exit[2] - 100*entry[2])^2)
        time = dist / airspeed 
        sector_times[sector] = convert(Int, round(time)) # made this round to integer bc time always needs to be discrete
    end

    return sector_times

    #durations = Dict{Int, Int}()  
    #prev_sector = nothing

    #for (x, y) in flight_line
        #sector = find_sector(x, y)
        #if isnothing(sector)
            #continue
        #end
        #if sector == prev_sector
            #durations[sector] += 1
        #else
            #durations[sector] = get(durations, sector, 0) + 1
        #end
        #prev_sector = sector
    #end

    #time_per_step = (step_size)*100 / airspeed
   # sector_times = Dict(k => round(v * time_per_step, digits=3) for (k, v) in durations)

    #return sector_times
end

# find what sectors a flight line crosses
function flight_path(row_number, airspeed, step_size)
    depart_airport = timetable[row_number, 3]
    arrive_airport = timetable[row_number, 5]
    depart_time = timetable[row_number, 7]

    flight_line = line_path(depart_airport, arrive_airport, step_size)
    min_sector_times = sector_durations(flight_line, airspeed)

    # flight_path = Vector{Tuple{Union{String, Int}, Float64}}()
    flight_lines = []
    flight_times = []
    flight_min_times = []



    # push!(flight_path, (depart_airport, 0))

    push!(flight_lines, depart_airport)
    push!(flight_times, 0)
    push!(flight_min_times, depart_time)


    seen_sectors = Set{Int}()

    for (x,y) in flight_line
        s = find_sector(x,y)
        if !(s in seen_sectors)
            # push!(flight_path, (s, min_sector_times[s]))
            push!(flight_lines, s)
            push!(flight_min_times, flight_min_times[end] + flight_times[end])
            push!(flight_times, min_sector_times[s])
            
            push!(seen_sectors, s)
        end
    end

    # push!(flight_path, (arrive_airport, 0))   
    push!(flight_lines, arrive_airport)
    push!(flight_min_times, flight_min_times[end] + flight_times[end])
    push!(flight_times, 0)
    

    # ok i changed this so that i could get the min sector times
    return flight_lines, flight_times, flight_min_times
end

airspeed = timetable[1, :airspeed]

all_paths = []
all_times = []
all_min_times = []

#find longest path
global max_length = 2
for i in 1:nrow(timetable)
    path, time, min_time = flight_path(i, airspeed, 0.01)

    println(path)
    push!(all_paths, path)
    push!(all_times, time)
    push!(all_min_times, min_time)

    if length(path) > max_length
        global max_length = length(path)
    end
end

# pad remaining paths with Os
padded_lines = [vcat(path, fill((0), max_length - length(path))) for path in all_paths]
padded_times = [vcat(time, fill((0), max_length - length(time))) for time in all_times]
padded_min_times = [vcat(min_time, fill((0), max_length - length(min_time))) for min_time in all_min_times]



result_lines = reduce(hcat, padded_lines)
result_times = reduce(hcat, padded_times)
result_min_times = reduce(hcat, padded_min_times)

println(result_times)

column_names = ["flight_$(i)" for i in 1:20]
padded_lines_df = DataFrame(result_lines, Symbol.(column_names))
padded_times_df = DataFrame(result_times, Symbol.(column_names))
padded_min_times_df = DataFrame(result_min_times, Symbol.(column_names))

print(padded_min_times_df)

CSV.write("flight_paths_anu.csv", padded_lines_df; writeheader = false)
CSV.write("min_times_anu.csv", padded_times_df; writeheader = false)
CSV.write("flight_min_times_anu.csv", padded_min_times_df; writeheader = false)