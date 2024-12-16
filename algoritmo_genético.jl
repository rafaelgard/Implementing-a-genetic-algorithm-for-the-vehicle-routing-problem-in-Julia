using Random
using CSV
using DataFrames
using Statistics
using Dates 
using Base.Threads

Random.seed!(10)

# Função de aptidão
function fitness!(cost_matrix::Matrix{Float64}, population, fitness::Vector{Float64}, num_ships::Int64)
    @threads for idx in 1:size(population, 1)
        total_cost = 0.0
        for i in 1:num_ships
            ship = i
            activity = population[idx, i]
            total_cost += cost_matrix[ship, activity]
        end
        fitness[idx] = total_cost
    end
    return nothing
end

# Crossover: Combinação de pais para criar um filho
function crossover(parent1::Vector{Int64}, parent2::Vector{Int64})
    n = length(parent1)
    point = rand(1:n-1)  # Ponto de corte
    child = vcat(parent1[1:point], setdiff(parent2, parent1[1:point]))
    return child
end

# Mutação: Alterar atividades aleatoriamente
function mutate(solution::Vector{Int64}, mutation_rate::Float64)
    if rand() < mutation_rate
        i, j = rand(1:length(solution), 2)  # Escolher dois índices aleatórios
        solution[i], solution[j] = solution[j], solution[i]  # Trocar atividades
    end
    return solution
end

function adaptive_truncation_rate(initial_rate::Float64, min_rate::Float64, k::Float64, t::Int64)
    return max(min_rate, initial_rate * exp(-k * t))
end

function adaptive_mutation_rate(initial_temp::Float64, current_temp::Float64, max_rate::Float64, min_rate::Float64)
    return min_rate + (max_rate - min_rate) * (current_temp / initial_temp)
end

# Algoritmo Genético Principal
function genetic_algorithm(
    cost_matrix::Matrix{Float64},
    num_generations::Int64,
    population_size::Int64,
    initial_temp::Float64,
    initial_truncation_rate::Float64,
    min_truncation_rate::Float64,
    k::Float64,
    max_mutation_rate::Float64,
    min_mutation_rate::Float64,
    show_iteration_results::Bool
)
    # Número de navios (linhas na matriz de custo)
    num_ships = size(cost_matrix, 1)

    # Inicializar população aleatória
    population = [shuffle(1:num_ships) for _ in 1:population_size]
    population = hcat(population...)'  # Formato matriz (cada linha é uma solução)

    fitness = zeros(Float64, population_size)  # Vetor de fitness

    # DataFrame para armazenar os resultados
    results = DataFrame(gen=Int[], best_cost=Float64[], mean_cost=Float64[], max_cost=Float64[])

    # Inicializar temperatura para simulated annealing
    current_temp = initial_temp

    # Loop principal
    for gen in 1:num_generations
        # Avaliar aptidão para cada indivíduo
        fitness!(cost_matrix, population, fitness, num_ships)

        # Estatísticas da geração
        best_cost = minimum(fitness)
        mean_cost = mean(fitness)
        max_cost = maximum(fitness)

        # Exibir resultados (opcional)
        if show_iteration_results
            println("Geração $gen | Melhor custo: $best_cost | Custo médio: $mean_cost | Custo máximo: $max_cost")
        end

        # Salvar estatísticas no DataFrame
        push!(results, (gen, best_cost, mean_cost, max_cost))

        # Ajustar taxa de truncamento (truncation_rate) dinamicamente
        truncation_rate = adaptive_truncation_rate(initial_truncation_rate, min_truncation_rate, k, gen)

        # Ajustar taxa de mutação dinamicamente (com simulated annealing)
        mutation_rate = adaptive_mutation_rate(initial_temp, current_temp, max_mutation_rate, min_mutation_rate)
        current_temp *= 0.99  # Reduzir temperatura

        # Seleção: Escolher os melhores indivíduos com base na taxa de truncamento
        num_to_select = max(round(Int, truncation_rate * population_size), population_size ÷ 2)
        sorted_indices = sortperm(fitness)
        best_solutions = population[sorted_indices[1:num_to_select], :]

        population = generate_new_population(best_solutions, mutation_rate, population_size, num_ships)
    end

    # Avaliar aptidão final para retornar melhor solução
    fitness!(cost_matrix, population, fitness, num_ships)
    best_index = argmin(fitness)
    best_solution = population[best_index, :]
    best_cost = fitness[best_index]

    return best_solution, best_cost, results
end

function generate_new_population(best_solutions, mutation_rate, population_size, num_ships)
    new_population = zeros(Int, population_size, num_ships)
    @threads for i in 1:population_size ÷ 2
        parent1 = best_solutions[i, :]
        parent2 = best_solutions[rand(1:size(best_solutions, 1)), :]
        child = mutate(crossover(parent1, parent2), mutation_rate)
        new_population[i, :] = child
        new_population[i + population_size ÷ 2, :] = mutate(parent1, mutation_rate)
    end
    return new_population
end

function get_geral_results(results::DataFrame)
    # Select the last line
    last_line = last(results, 1)

    best_cost = last_line[1, "best_cost"]
    mean_cost = last_line[1, "mean_cost"]
    max_cost = last_line[1, "max_cost"]
    
    return best_cost, mean_cost, max_cost
end

function get_time(inicio::DateTime, fim::DateTime)
    # Calcula a diferença entre agora e o início
    tempo_decorrido = fim - inicio
    
    # Converte para segundos
    return Millisecond(tempo_decorrido).value / 1000.0
end

function grid_search_params(cost_matrix::Matrix{Float64}, show_iteration_results::Bool)

    geral_results = DataFrame(num_generations=Int64[], population_size=Int64[], initial_temp=Float64[], min_mutation_rate=Float64[], max_mutation_rate=Float64[], initial_truncation_rate=Float64[], min_truncation_rate=Float64[], k=Float64[], best_cost=Float64[], mean_cost=Float64[], max_cost=Float64[], total_time=Float64[])

    experiment_id = 1
    initial_temps = [100.0, 1000.0]
    ks = [0.01, 0.05, 0.1]
    min_mutation_rates = [0.01, 0.05, 0.1]
    max_mutation_rates = [0.3]
    min_truncation_rates = [0.1, 0.3]
    initial_truncation_rates = [0.7]

    for min_truncation_rate in min_truncation_rates
        for initial_truncation_rate in initial_truncation_rates
            for initial_temp in initial_temps
                for k in ks
                    for min_mutation_rate in min_mutation_rates 
                        for max_mutation_rate in max_mutation_rates 
                            for num_generations in [100, 500, 1000, 5000]
                                for population_size in [100, 500, 1000]
                                    
                                    inicio = now()

                                    best_solution, best_cost, results = genetic_algorithm(cost_matrix, num_generations, population_size, initial_temp, initial_truncation_rate, min_truncation_rate, k, max_mutation_rate, min_mutation_rate, false)

                                    fim = now()

                                    total_time = get_time(inicio, fim)

                                    if show_iteration_results
                                        println("experiment_id: $experiment_id")
                                        println("num_generations: $num_generations - population_size: $population_size - initial_temp: $initial_temp - initial_truncation_rate: $initial_truncation_rate - min_truncation_rate: $min_truncation_rate")
                                        println("max_mutation_rate: $max_mutation_rate - min_mutation_rate: $min_mutation_rate - k: $k - best_cost: $best_cost - total_time: $total_time")
                                        println("Melhor solução: ", best_solution)
                                        println("=====================================================================================================")
                                    end

                                    best_cost, mean_cost, max_cost = get_geral_results(results)

                                    push!(geral_results, (num_generations, population_size, initial_temp, min_mutation_rate, max_mutation_rate, initial_truncation_rate, min_truncation_rate, k, best_cost, mean_cost, max_cost, total_time))

                                    experiment_id += 1

                                end
                            end
                        end
                    end
                end
            end
        end
    end

    # Salvar resultados em CSV
    CSV.write("results/geral_results_hybrid.csv", geral_results)
end

# Configurações
n_rows = 100  # Número de linhas
n_cols = 100  # Número de colunas
min_value = 10  # Valor mínimo dos elementos
max_value = 50  # Valor máximo dos elementos

# Geração da matriz aleatória
cost_matrix = [rand(min_value:max_value) for _ in 1:n_rows, _ in 1:n_cols]

# Convertendo para Float64 (se necessário)
cost_matrix = Float64.(cost_matrix)

grid_search_params(cost_matrix, true)
