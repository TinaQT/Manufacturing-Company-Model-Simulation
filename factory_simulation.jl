using DataStructures, Distributions, StableRNGs, Dates, Printf

# Define the Event first
abstract type Event end

struct Arrival <: Event # order arrives
    id::Int64           # order id
    time::Float64       # the time of event
end

mutable struct Departure <: Event # order finishes
    id::Int64                     # order id
    time::Float64                 # the time of event
end

mutable struct Breakdown <: Event # the machine breakdown
    id::Int64                     # order id
    time::Float64                 # the time of event
end

mutable struct Repair <: Event # the machine is repaired
    id::Int64                  # order id
    time::Float64              # the time of event
end


# Entity
mutable struct Order
    id::Int64                   # the unique order id
    arrival_time::Float64       # the order arrival time
    start_service_time::Float64 # the time when the order start service
    completion_time::Float64    # the time when the order is finished
    interrupted::Int64          # the flag if the production is interrupted due to breakdown
end

# generate a newly arrived order and the time is unknown
Order(id::Int64, arrival_time::Float64) = Order(id, arrival_time, Inf, Inf, 0)

# Parameter
struct Parameters
    seed::Int                         # set the seed
    T::Float64                        # set the time
    mean_interarrival::Float64        # set the mean interarrival time
    mean_construction_time::Float64   # set the mean construction time
    mean_interbreakdown_time::Float64 # set the interbreakdown time
    mean_repair_time::Float64         # set the mean repair time
end


# Define the system state
mutable struct SystemState
    time::Float64                             # the simulation time
    event_queue::PriorityQueue{Event,Float64} # keep track of future arrivals/breakdown
    waiting_queue::Queue{Order}               # the waiting queues
    in_service::Union{Nothing, Order}         # the order in service
    n_entities::Int64                         # the number of entities to have been served
    n_events::Int64                           # the number of events to have occured and queued
    machine_status::Int64                     # if machine is working or breakdown, either 0 or 1
end


# Create an initial state
function SystemState()
    t0 = 0.0 # initial time
    init_event_queue = PriorityQueue{Event,Float64}()
    init_waiting_queue = Queue{Order}()
    init_in_service = nothing
    init_n_entities = 0
    init_n_events = 0
    init_machine_status = 0
    return SystemState(t0, init_event_queue, init_waiting_queue, init_in_service, init_n_entities, init_n_events, init_machine_status)
end


# Five random number generators
struct RandomNGs
    rng::StableRNGs.LehmerRNG
    interarrival_time::Function
    construction_time::Function
    interbreakdown_time::Function
    repair_time::Function
end

function RandomNGs(P::Parameters)
    rng = StableRNGs.LehmerRNG(P.seed)
    interarrival_time() = rand(rng, Exponential(P.mean_interarrival))
    construction_time() = P.mean_construction_time
    interbreakdown_time() = rand(rng, Exponential(P.mean_interbreakdown_time))
    repair_time() = rand(rng, Exponential(P.mean_repair_time))

    return RandomNGs(rng, interarrival_time, construction_time, interbreakdown_time, repair_time)
end


# Intialise function
function initialise(P::Parameters)
    R = RandomNGs(P)       # create the RNGs
    system = SystemState() # create the initial state structure

    # add an arrival at time 0.0
    t0 = 0.0
    # system.n_events += 1 # keep track of events
    enqueue!(system.event_queue, Arrival(0,t0), t0)

    # add a breakdown at time 150.0
    t1 = 150.0
    system.n_events += 1
    enqueue!(system.event_queue, Breakdown(system.n_events, t1), t1)

    return (system, R)
end


# Move a lawnmower order to machine
function move_order_to_machine!(system::SystemState, R::RandomNGs)
    # move order from waiting list to machine
    system.in_service = dequeue!(system.waiting_queue)
    system.in_service.start_service_time = system.time
    system.in_service.completion_time = system.time + R.construction_time()

    # create a departure event for this order
    system.n_events += 1
    departure_event = Departure(system.n_events, system.in_service.completion_time)
    enqueue!(system.event_queue, departure_event, system.in_service.completion_time)
    return nothing
end


# Update the arrival event
function update!(system::SystemState, P::Parameters, R::RandomNGs, event::Arrival)
    # system.time = event.time 

    system.n_entities += 1 # new order enter the system

    # create an arriving order and add it to the queue
    new_order = Order(system.n_entities, event.time)
    enqueue!(system.waiting_queue, new_order)

    # generate next arrival and add it to the event queue
    # system.n_events += 1
    future_arrival = Arrival(system.n_events, system.time + R.interarrival_time())
    enqueue!(system.event_queue, future_arrival, future_arrival.time)

    # if the machine is working and available, the order goes to machine
    if (system.in_service === nothing) && (system.machine_status == 0)
        move_order_to_machine!(system, R)
    end
    return nothing
end


# Update the departure event
function update!(system::SystemState, P::Parameters, R::RandomNGs, event::Departure)
    # system.time = event.time
    
    departing_order = deepcopy(system.in_service)
    system.in_service = nothing # set the machine as available

    # if the machine is working and the waiting_queue is not empty, goes to machine
    if (!isempty(system.waiting_queue)) && (system.machine_status == 0)
        move_order_to_machine!(system, R)
    end

    departing_order.completion_time = system.time # update
    return departing_order
end


# Update the breakdown event
function update!(system::SystemState, P::Parameters, R::RandomNGs, event::Breakdown)
    # system.time = event.time

    # generate repair event and add it to the event queue
    # system.n_events += 1
    new_repair = Repair(system.n_events, system.time + R.repair_time())
    enqueue!(system.event_queue, new_repair, new_repair.time)

    # change machine status in system state
    system.machine_status = 1

    # change machine interruption flag if the machine is in service
    if system.in_service !== nothing
        system.in_service.interrupted = 1

        departure_event = nothing
        for e in system.event_queue
            if e isa Departure && e.id == (system.n_events - 1)
                departure_event = e
                break
            end
        end

        if departure_event !== nothing
            departure_event.time += R.repair_time()
        end
    end

    
    return nothing
end


# Update the repair event
function update!(system::SystemState, P::Parameters, R::RandomNGs, event::Repair)
    # system.time = event.time

    # change machine status in system state
    system.machine_status = 0

    # generate the next breakdown event and add it to the event queue
    # system.n_events += 1
    next_breakdown = Breakdown(system.n_events, system.time + R.interbreakdown_time())
    enqueue!(system.event_queue, next_breakdown, next_breakdown.time)

    # move an order to machine if it is not busy
    if (system.in_service === nothing) && (!isempty(system.waiting_queue))
        move_order_to_machine!(system, R)
    end
    return nothing
end


# Write the parameters
function write_parameters(output::IO, P::Parameters)
    T = typeof(P)
    for name in fieldnames(T)
        println(output, "# parameter $name = $(getfield(P, name))")
    end
end

write_parameters(P::Parameters) = write_parameters(stdout, P)


# Write the metadata
function write_metadata(output::IO)
    (path, prog) = splitdir(@__FILE__)
    println(output, "# file created by code in $(prog)")
    t = now()
    println(output, "# file created on $(Dates.format(t, "yyyy-mm-dd at HH:MM:SS"))")
end


# Write state
function write_state(event_file::IO, system::SystemState, P::Parameters, event::Event; debug_level::Int=0)
    @printf(event_file,
            "%12.3f, %6d, %9s, %4d, %4d, %4d, %4d",
            system.time,
            event.id,
            typeof(event),
            length(system.event_queue),
            length(system.waiting_queue),
            system.in_service === nothing ? 0 : 1,
            system.machine_status
            )

    @printf(event_file, "\n")
end


# Write entity header
function write_entity_header(entity_file::IO, entity)
    T = typeof(entity)
    x = Array{Any,1}(undef, length( fieldnames(typeof(entity)) ) )
    for (i,name) in enumerate(fieldnames(T))
        tmp = getfield(entity,name)
        if isa(tmp, Array)
            x[i] = join( repeat( [name], length(tmp) ), ',' )
        else
            x[i] = name
        end
    end
    println( entity_file, join( x, ',') )
end


# Write entity
function write_entity(entity_file::IO, entity)
    T = typeof( entity )
    x = Array{Any,1}(undef,length( fieldnames(typeof(entity)) ) )
    for (i,name) in enumerate(fieldnames(T))
        tmp = getfield(entity,name)
        if isa(tmp, Array)
            x[i] = join( tmp, ',' )
        else
            x[i] = tmp
        end
    end
    println( entity_file, join( x, ',') )
end


# write the run! function
function run!( system::SystemState, P::Parameters, R::RandomNGs, fid_state::IO, fid_entities::IO)
    # main simulation loop
    while system.time < P.T
        if P.seed == 1 && system.time <= 1000.0
            println("$(system.time): ") # debug information for first few events whenb seed = 1
        end

        # grab the next event from the event queue
        (event, time) = dequeue_pair!(system.event_queue)
        system.time = time # advance system time to the new arrival
        system.n_events += 1      # increase the event counter
        
        # write out state data
        write_state(fid_state, system, P, event)
        
        # update the system based on the next event, and spawn new events. 
        # return departed order.
        departure = update!(system, P, R, event )

        
        # write out entity data if it was a departure from the system
        if departure !== nothing 
            write_entity( fid_entities, departure )
        end
    end
    return system
end

# end of code