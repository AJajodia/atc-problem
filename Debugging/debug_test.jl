sectors_df = DataFrame(CSV.File("debug_airport_sectors.csv"))

function Tjf(f, j)
    start_time = Int.(start_df[j, f]) -1
    end_time = start_time + buffer_time
    return start_time:end_time
end

Tjf(1,1)
