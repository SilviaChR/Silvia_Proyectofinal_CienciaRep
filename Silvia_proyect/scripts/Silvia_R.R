# install_github("jtextor/dagitty/r")
require(dagitty)

# install.packages("ggdag")
require(ggdag)

# install.packages("wesanderson")
require(wesanderson)

## Representación de  diagrama causal  

#Quiero conocer el efeto de la disponibilidad  de refugios(D) sobre el % de superposición de los ámbitos de descanso (S) entre los grupos de Thyroptera tricolor. Pero tambien deseo saber  si el tamaño del grupo (TG) afecta % de superposicion de los ámbitos de descanso. 

#Modelo con un DAG:
  
# x = D
# z = TG
# y = S

# Crear DAG
dag1 <- dagify(S ~ D,
                   S ~ TG,
                   exposure = "D",
                   outcome = "S")

# compactar
tidy_dagitty(dag1)

# graficar  
ggdag(dag1, layout = "circle") + theme_dag() 

# La densidad de  refugios y el Tamaño del grupo son independientes entre sí, por lo que en mi analisis debería condicionar por ninguna de estas dos variables.




###
En esta función se  crean las variables  para el número de grupos,  número de individuos por grupo, número de hojas  dentro de  un área de 200 x 300 m2.  

sim_habitat <- function(n_groups, n_indiv, n_leaves = 3000, steps = 10000, sig2 = 0.7, plot = TRUE, xlim = c(0, 300), ylim = c(0, 200)) {
  
  
  if (n_leaves >= steps){
    cat(crayon::green(' Alto ahí, puede tener más hojas que steps\n'))
    stop()
  }
  
  t <- 0:steps  # Saltos de tiempo 
  
  ## Primero, se crea un set simulación de desviaciones con σ2= 0.7, para los valores de x
  x <- rnorm(n = length(t) - 1, sd = sqrt(sig2))
  
  ## Ahora se  calcula la suma acumulada de las desviaciones 
  cx <- c(0, cumsum(x))
  # plot(t, cx, type = "l", ylim = range(cx))
  
  ## Se repiten los dos pasos anteriores para los valores de y
  y <- rnorm(n = length(t) - 1, sd = sqrt(sig2))
  ## suma acumulada de las desviaciones para valores de y
  cy <- c(0, cumsum(y))
  
  # Simulación de hojas disponibles como refugios
  
  sel_positions_x <- cumsum((rbinom(n_leaves, size = 2, prob = 0.1) * 400) + 50)
  sel_positions_y <- cumsum((rbinom(n_leaves, size = 2, prob = 0.1) * 400) + 50)
  
  sel_positions_x <- (sel_positions_x / max(sel_positions_x)) * steps
  sel_positions_y <- (sel_positions_y / max(sel_positions_y)) * steps
  
  slxs <- cx[sel_positions_x]
  slys <- cy[sel_positions_y]
  
  slxs <- slxs + abs(min(slxs))
  slxs <- (slxs / max(slxs)) * xlim[2]
  slys <- slys + abs(min(slys))
  slys <- (slys / max(slys)) * ylim[2]
  
  # Obtenemos las coordenadas  para el número de hojas disponibles como refugio
  coor_df <- data.frame(lon= slxs, lat = slys)
  
  if (plot)
    plot(coor_df$lon, coor_df$lat, pch = 20, col = adjustcolor("green", alpha.f = 0.3), xlim = xlim + c(-10, 10), ylim = ylim + c(-10, 10))
  
  
  return(coor_df)
}

####
#Función ubicaión de grupos 

# Simular las coordenadas de ubicación para 10 grupos de murciélagos 
sim_home_range <- function(leaf_coors, groups, radius_constant = 6){
  
  if (groups >= nrow(leaf_coors)){
    cat(crayon::green('No se puede tener más grupos q hojas \n'))
    stop()
  }
  # Determinamos el tamaño  para los 10 grupos, usamos una probabilidaded 0.6 para que los tamaños de grupo tengan  sentido segun lo visto  en la naturaleza 
  group_sizes <- rbinom(n = groups, 10, prob = 0.6)
  
  # extraemos una hoja central para cada grupo  
  leaves <- sample(1:nrow(leaf_coors), length(group_sizes))
  # obtenemos  las coordenanadas para cada hoja central 
  centers <- leaf_coors[leaves, ]  
  
  centers$group_size <- group_sizes
  
  centers$leaves <- leaves
  
  # Se calculan todas las distancias posibles entre la hoja central  mediante una matris de distancia  entre las hojas disponibles.
  dist_leaves <- as.matrix(dist(leaf_coors))
  
  group_leaves_l <- lapply(1:nrow(centers), function(x){
    
    dists_to_center <- dist_leaves[centers$leaves[x], ]
    # se seleccionan las hojas  cuya distancia al centro sea menor que el tamaño del grupo multiplicado por un radio constante 
    selec_leaves <- dists_to_center[dists_to_center < centers$group_size[x] * radius_constant] 
    
    # Se crea un data frame de las hojas selecionadas y sus respectivas coordenadas 
    selec_leaves_df <- leaf_coors[names(selec_leaves), ]
    
    selec_leaves_df$leaf_id <- names(selec_leaves)
    
    selec_leaves_df$dist_to_center <- selec_leaves
    
    selec_leaves_df$group_size <- centers$group_size[x]
    
    selec_leaves_df$id <- x
    
    return(selec_leaves_df)
    
  })
  group_leaves <- do.call(rbind, group_leaves_l)
  
  return(group_leaves)
}

###
get_home_range <- function(X, percent = 95){

Y <- SpatialPointsDataFrame(X[, c("lat", "lon")], as.data.frame(X$id))

ud <- try(kernelUD(Y), silent = TRUE)

areas <- unlist(as.data.frame(kernel.area(ud, percent = percent))[1,, drop = TRUE])

areas_df <- data.frame(group = 1:length(areas), area = areas, group_size = sapply(unique(X$id), function(e) X$group_size[X$id == e][1]))

return(areas_df)
}

resample_leaves <- function(X, n = 30){
  
  out <- lapply(unique(X$id), function(x){
    
    Y <- X[X$id == x, ]
    
    if (nrow(Y) > n) 
      Y <- Y[sample(1:nrow(Y), n), ]
    
    return(Y)
    
  })
  
  return(do.call(rbind, out))
  
}

###
library(adehabitatHR)

leaf_coors <- sim_habitat(n_leaves = 1000, plot = FALSE)

sims <- sim_home_range(leaf_coors = leaf_coors, groups = 11, radius_constant = 6)

tab <- table(sims$id)

sims <- sims[!sims$id %in% names(tab[tab < 5]), ]

range_and_size <- get_home_range(X = sims)


mod <- lm(area ~ group_size, data = range_and_size)
summary(mod)

plot(range_and_size$group_size, range_and_size$area)

abline(mod, col = "red")

resamp_sims <- resample_leaves(sims, n = 30)


table(resamp_sims$id)


resample_range_and_size <- get_home_range(X = resamp_sims)


mod2 <- lm(area ~ group_size, data = resample_range_and_size)
summary(mod2)

plot(resample_range_and_size$group_size, resample_range_and_size$area)

abline(mod2, col = "red")




