#' Load in a cooler (.cool) file 
#' 
#' @param cooler The path to the .cool file
#' @param balancing T/F
#' @param scale_BP Double
#' @param scale_cis T/F
#' resolution Integer
#' norm String
#' @returns 
loadCooler = function(cooler, balancing = T, scale_bp = NULL, scale_cis = F, resolution = 10e3, norm = 'weight'){
  bins_name = "bins"
  pixels_name = "pixels"
  ABS = NULL
  SIG = NULL
  # check if it contains bins or resolution groups:
  if(any(grepl("/resolutions",rhdf5::h5ls(cooler)[,1]))){
    # crap, one of those cooler-files...
    # lets start with finding all resolutions...
    cooler_res <- sapply(rhdf5::h5ls(cooler)[,1], 
                         function(x){ x <- gsub("/resolutions/","", x)  })
    cooler_res <- as.numeric(unique(cooler_res[!grepl('/',cooler_res)]))
    if(!resolution %in% cooler_res){
      stop('Cool file does not include a resolution of ', 
           format(resolution, scientific = FALSE),
           ".\nAvailable resolutions are: ", 
           paste0(cooler_res, collapse = ", "))
    }
    ABS = data.table::as.data.table(
      rhdf5::h5read(file = cooler,
                    name = paste0("/resolutions/",
                                  format(resolution, scientific = FALSE), 
                                  "/", bins_name)))
    
    ### Previously, only checked if Knight-Ruiz (KR) normalization is done, else asigns NA to all norm weight values
    #if('KR' %in% colnames(ABS)) {
    #  ABS$weight <- 1/ABS$KR
    #}

    ### Now, check if norm parameter exists in file, so user can specify any norm column in the file
    if (norm %in% colnames(ABS)) {
      print(paste0("Using ",norm))
      ABS$weight <- ABS[, ..norm]
    }
    else {
      balancing = F
      stop(paste0(norm,' not found in cooler.'))
      ABS$weight <- NA
    }
    
    ABS <- ABS[, c("chrom", "start", "end",  "weight" ), with = F]
    ABS$bin = 1:nrow(ABS)
    SIG = data.table::as.data.table(
      rhdf5::h5read(file = cooler,
                    name = paste0("/resolutions/",
                                  format(resolution, scientific = FALSE), 
                                  "/", pixels_name)))
  } else {
    ABS = data.table::as.data.table(rhdf5::h5read(file = cooler,
                                                  name = bins_name))
    if (norm %in% colnames(ABS)) {
      warning(paste0("Using ",norm))
      ABS$weight <- ABS[, ..norm]
    }
    else {
      balancing = F
      warning(paste0(normalization,' not found in cooler.'))
      ABS$weight <- NA
    }
    
    ABS <- ABS[, c("chrom", "start", "end",  "weight" ), with = F]
    ABS$bin = 1:nrow(ABS)
    SIG = data.table::as.data.table(rhdf5::h5read(file = cooler,
                                                  name = pixels_name))
    
  }
  
  rhdf5::h5closeAll()
  
  # handle nan and NA in ABS$weigth
  ABS$weight[is.nan(ABS$weight)] <- 0
  ABS$weight[is.na(ABS$weight)] <- 0
  
  colnames(SIG) = paste0('V', 1:3)
  SIG[,1] = SIG[,1] + 1
  SIG[,2] = SIG[,2] + 1
  
  if(balancing){
    SIG = balance_cooler(ABS, SIG)
  }
  
  ABS$weight = NULL
  colnames(ABS) = paste0('V', 1:4)
  
  if (!is.null(scale_bp)) {
    
    if(scale_cis){
      
      chromRange = ABS[ , .(first = min(V4)), by = V1]
      chromRange = chromRange[order(chromRange$first),]
      
      F1 = findInterval(SIG$V1, chromRange$first)
      F2 = findInterval(SIG$V2, chromRange$first)
      
      SIG$V3 <- scale_bp * SIG$V3 / sum(SIG[ifelse(F1 == F2, T, F), 3])
      
    } else {
      SIG$V3 <- scale_bp * SIG$V3 / sum(SIG$V3)
    }
    
  }
  
  
  SIG <- as.data.frame(SIG)
  SIG <- data.table::data.table(apply(SIG, 2, as.vector))
  data.table::setkey(SIG, "V1", "V2")
  
  ABS <- as.data.frame(ABS)
  ABS$V1 <- as.character(as.vector(ABS$V1))
  ABS$V2 <- as.numeric(as.vector(ABS$V2))
  ABS$V3 <- as.numeric(as.vector(ABS$V3))
  ABS$V4 <- as.numeric(as.vector(ABS$V4))
  ABS <- data.table::data.table(ABS)
  data.table::setkey(ABS, "V1", "V2")
  
  return(list(SIG, ABS))
}



balance_cooler = function(ABS, SIG){
  
  WEIGHTS = data.table::data.table(stats::setNames(ABS[, c('bin','weight'),],
                                                   c('V1_id','V1_weight')),
                                   key = 'V1_id')
  WEIGHTS$V1_weight[is.nan(WEIGHTS$V1_weight)] = 1
  
  data.table::setkey(SIG, 'V1')
  SIG <- SIG[WEIGHTS, nomatch = 0]
  
  colnames(WEIGHTS) = c('V2','V2_weight')
  
  data.table::setkey(WEIGHTS, 'V2')
  data.table::setkey(SIG, 'V2')
  
  SIG <- SIG[WEIGHTS, nomatch = 0]
  
  SIG$weight = SIG$V1_weight * SIG$V2_weight
  SIG$V3 = SIG$V3*SIG$weight
  
  return(SIG[, c(1,2,3)])
}
