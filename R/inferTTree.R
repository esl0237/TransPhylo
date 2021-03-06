#' Infer transmission tree given a phylogenetic tree
#' @param ptree Phylogenetic tree
#' @param w.shape Shape parameter of the Gamma probability density function representing the generation time
#' @param w.scale Scale parameter of the Gamma probability density function representing the generation time 
#' @param ws.shape Shape parameter of the Gamma probability density function representing the sampling time
#' @param ws.scale Scale parameter of the Gamma probability density function representing the sampling time 
#' @param w.mu Mean of the Gamma probability density function representing the generation time, used with w.sigma to replace the shape and scale parameters 
#' @param w.sigma Standard deviation of the Gamma probability density function representing the generation time
#' @param ws.mu Mean of the Gamma probability density function representing the sampling time, used with ws.sigma to replace the shape and scale parameters  
#' @param ws.sigma Standard deviation of the Gamma probability density function representing the sampling time
#' @param mcmcIterations Number of MCMC iterations to run the algorithm for
#' @param thinning MCMC thinning interval between two sampled iterations
#' @param startNeg Starting value of within-host coalescent parameter Ne*g
#' @param R0 Starting value of R0, one of startOff.r or startOff.p must also be specified  
#' @param startOff.r Starting value of parameter off.r
#' @param startOff.p Starting value of parameter off.p
#' @param startPi Starting value of sampling proportion pi
#' @param updateNeg Whether of not to update the parameter Ne*g
#' @param updateOff.r Whether or not to update the parameter off.r
#' @param updateOff.p Whether or not to update the parameter off.p
#' @param updatePi Whether or not to update the parameter pi
#' @param startCTree Optional combined tree to start from
#' @param updateTTree Whether or not to update the transmission tree
#' @param optiStart Whether or not to optimise the MCMC start point
#' @param dateT Date when process stops (this can be Inf for fully simulated outbreaks)
#' @param penalize whether to penalize transmission trees probability based on the \strong{epiData}
#' @param trackPenalty whether to save information about the penalty amounts as well as what part of the tree caused each penalty
#' @param prulebreak Probability that each penalty for a tree is valid  
#' @inheritParams epiPenTTree
#' @return posterior sample set of transmission trees
#' @export
inferTTree = function(ptree, w.shape=2, w.scale=1, ws.shape=w.shape, ws.scale=w.scale, w.mu, w.sigma, ws.mu, ws.sigma, mcmcIterations=1000,
                      thinning=1, startNeg=100/365, R0, startOff.r=1, startOff.p=0.5, startPi=0.5, updateNeg=TRUE,
                      updateOff.r=TRUE, updateOff.p=FALSE, updatePi=TRUE, startCTree=NA, updateTTree=TRUE,
                      optiStart=TRUE, dateT = Inf, epiData, penalize = TRUE, trackPenalty = FALSE, prulebreak = 0.8){
#  memoise::forget(getOmegabar)
#  memoise::forget(probSubtree)
  ptree$ptree[,1]=ptree$ptree[,1]+runif(nrow(ptree$ptree))*1e-10#Ensure that all leaves have unique times
  for (i in (ceiling(nrow(ptree$ptree)/2)+1):nrow(ptree$ptree)) for (j in 2:3) 
    if (ptree$ptree[ptree$ptree[i,j],1]-ptree$ptree[i,1]<0) 
      stop("The phylogenetic tree contains negative branch lengths!")
  
  # calculate shape and scale if provided mu & sigma for sampling and generation dist. 
  if (!missing(w.mu) && !missing(w.sigma)) {
    w.shape <- (w.mu / w.sigma)^2
    w.scale <- (w.sigma^2 / w.mu)
  }
  
  if (!missing(ws.mu) && !missing(ws.sigma)) {
    ws.shape <- (ws.mu / ws.sigma)^2
    ws.scale <- (ws.sigma^2 / ws.mu)
  }
  
  if(missing(startOff.r) && !missing(startOff.p) && !missing(R0)){
    # if given p and R0 then solve for r
    startOff.r <- (R0*(1-startOff.p))/startOff.p
  } else if(!missing(startOff.r) && missing(startOff.p) && !missing(R0)) { 
    # if given R0 and r and don't specify p  assume p = 0.5 ==> R0 = r 
    startOff.p <- 0.5 
  }
  
  #MCMC algorithm
  neg <- startNeg
  off.r <- startOff.r
  off.p <- startOff.p
  pi <- startPi
  if (is.na(sum(startCTree))) ctree <- makeCtreeFromPTree(ptree,ifelse(optiStart,off.r,NA),off.p,neg,pi,w.shape,w.scale,ws.shape,ws.scale,dateT)#Starting point 
  else ctree<-startCTree
  ttree <- extractTTree(ctree)
  acceptNumNeg <- 0
  acceptNumR <- 0 
  acceptNumP <- 0
  acceptNumPi <- 0
  acceptNumTTree <- 0 
  
  penalize <- !missing(epiData) && penalize
  trackPenalty <- !missing(epiData) && trackPenalty
  
  if(trackPenalty){
    penalty <- epiPenTTree(ttree, epiData, penaltyInfo = trackPenalty)
    penalty.info <- penalty[2] 
    penalty <- unlist(penalty[1])
  } else if(penalize) {
    penalty <- unlist(epiPenTTree(ttree, epiData, penaltyInfo = trackPenalty))
  }
  logPen <- ifelse(penalize,penalty*log(prulebreak),0)
  
  
  record <- vector('list',mcmcIterations/thinning)
  pTTree <- probTTree(ttree$ttree,off.r,off.p,pi,w.shape,w.scale,ws.shape,ws.scale,dateT) - logPen
  pPTree <- probPTreeGivenTTree(ctree,neg) 
  
  if(is.infinite(pTTree)){
    stop("pTTree is infinite, stopping inference")
  } 
  
  if(is.infinite(pPTree)){
    stop("pPTree is infinite, stopping inference")
  } 
  
  pb <- utils::txtProgressBar(min=0,max=mcmcIterations,style = 3)
  for (i in 1:mcmcIterations) {#Main MCMC loop
    if (i%%thinning == 0) {
      #Record things 
      utils::setTxtProgressBar(pb, i)
      #message(sprintf('it=%d,neg=%f,off.r=%f,off.p=%f,pi=%f,Prior=%e,Likelihood=%f,n=%d',i,neg,off.r,off.p,pi,pTTree,pPTree,nrow(extractTTree(ctree))))
      record[[i/thinning]]$ctree <- ctree
      record[[i/thinning]]$pTTree <- pTTree 
      record[[i/thinning]]$pPTree <- pPTree 
      record[[i/thinning]]$neg <- neg 
      record[[i/thinning]]$off.r <- off.r
      record[[i/thinning]]$off.p <- off.p
      record[[i/thinning]]$pi <- pi
      record[[i/thinning]]$w.shape <- w.shape
      record[[i/thinning]]$w.scale <- w.scale
      record[[i/thinning]]$ws.shape <- ws.shape
      record[[i/thinning]]$ws.scale <- ws.scale
      record[[i/thinning]]$acc.rate.neg <- acceptNumNeg/i
      record[[i/thinning]]$acc.rate.updateOff.r <- acceptNumR/i
      record[[i/thinning]]$acc.rate.updateOff.p <- acceptNumP/i
      record[[i/thinning]]$acc.rate.updateOff.pi <- acceptNumPi/i
      record[[i/thinning]]$acc.rate.ttree <- acceptNumTTree/i
      record[[i/thinning]]$posterior <- pTTree+pPTree
      if(trackPenalty){
        record[[i/thinning]]$penalty.exposure <- unname(penalty[1])
        record[[i/thinning]]$penalty.contact <- unname(penalty[2])
        record[[i/thinning]]$penalty.location <- unname(penalty[3])
        record[[i/thinning]] <- c(record[[i/thinning]],penalty.info)
      }
      record[[i/thinning]]$source <- ctree$ctree[ctree$ctree[which(ctree$ctree[,4]==0),2],4]
      if (record[[i/thinning]]$source<=length(ctree$nam)) record[[i/thinning]]$source=ctree$nam[record[[i/thinning]]$source] else record[[i/thinning]]$source='Unsampled'
    }
    
    # update the penality for the current transmission tree 
    if(trackPenalty){
      penalty <- epiPenTTree(ttree, epiData, penaltyInfo = trackPenalty)
      penalty.info <- penalty[2] 
      penalty <- unlist(penalty[1])
    } else if(penalize) {
      penalty <- unlist(epiPenTTree(ttree, epiData, penaltyInfo = trackPenalty))
    }
    logPen <- ifelse(penalize,penalty*log(prulebreak),0)
    
    if (is.na(logPen)){
      message("penalty is NA, stopping inference and returning record")
      return(record)
    } 
    
    if (updateTTree) {
      #Metropolis update for transmission tree 
      prop <- proposal(ctree$ctree) 
      ctree2 <- list(ctree=prop$tree,nam=ctree$nam)
      ttree2 <- extractTTree(ctree2)
      pTTree2 <- probTTree(ttree2$ttree,off.r,off.p,pi,w.shape,w.scale,ws.shape,ws.scale,dateT) - logPen
      pPTree2 <- probPTreeGivenTTree(ctree2,neg) 
      
      if(is.infinite(pTTree2)){
        message("pTTree2 is infinite in Metropolis update for transmission tree, stopping inference and returning record")
        return(record)
      } 
      
      if(is.infinite(pPTree2)){
        message("pPTree2 is infinite in Metropolis update for transmission tree, stopping inference and returning record")
        return(record)
      } 
      
      if (log(runif(1)) < log(prop$qr)+pTTree2 + pPTree2-pTTree-pPTree){ 
        acceptNumTTree <- acceptNumTTree + 1 
        ctree <- ctree2 
        ttree <- ttree2
        pTTree <- pTTree2 
        pPTree <- pPTree2 
      } 
    }
    
    if (updateNeg) {
      #Metropolis update for Ne*g, assuming Exp(1) prior 
      neg2 <- abs(neg + (runif(1)-0.5)*0.5)
      pPTree2 <- probPTreeGivenTTree(ctree,neg2) 
      
      if(is.infinite(pPTree2)){
        message("pPTree2 is infinite in Metropolis update for Ne*g, stopping inference and returning record")
        return(record)
      }
      
      if (log(runif(1)) < pPTree2-pPTree-neg2+neg){
          acceptNumNeg <- acceptNumNeg + 1  
          neg <- neg2
          pPTree <- pPTree2
          
        } 
    }
    
    if (updateOff.r) {
      #Metropolis update for off.r, assuming Exp(1) prior 
      off.r2 <- abs(off.r + (runif(1)-0.5)*0.5)
      pTTree2 <- probTTree(ttree$ttree,off.r2,off.p,pi,w.shape,w.scale,ws.shape,ws.scale,dateT) - logPen
      
      if(is.infinite(pTTree2)){
        message("pTTree2 is infinite in Metropolis update for off.r, stopping inference and returning record")
        return(record)
      } 
      
      if (log(runif(1)) < pTTree2-pTTree-off.r2+off.r)  {
        acceptNumR <- acceptNumR + 1 
        off.r <- off.r2
        pTTree <- pTTree2
      }
    }
    
    if (updateOff.p) {
      #Metropolis update for off.p, assuming Unif(0,1) prior 
      off.p2 <- abs(off.p + (runif(1)-0.5)*0.1)
      if (off.p2>1) off.p2=2-off.p2
      pTTree2 <- probTTree(ttree$ttree,off.r,off.p2,pi,w.shape,w.scale,ws.shape,ws.scale,dateT) - logPen
      
      if(is.infinite(pTTree2)){
        message("pTTree2 is infinite in Metropolis update for off.p, stopping inference and returning record")
        return(record)
      } 
      
      if (log(runif(1)) < pTTree2-pTTree)  {
        acceptNumP <- acceptNumP + 1 
        off.p <- off.p2
        pTTree <- pTTree2
      }
    }

    if (updatePi) {
      #Metropolis update for pi, assuming Unif(0.01,1) prior 
      pi2 <- pi + (runif(1)-0.5)*0.1
      if (pi2<0.01) pi2=0.02-pi2
      if (pi2>1) pi2=2-pi2
      pTTree2 <- probTTree(ttree$ttree,off.r,off.p,pi2,w.shape,w.scale,ws.shape,ws.scale,dateT) - logPen
      
      if(is.infinite(pTTree2)){
        message("pTTree2 is infinite in Metropolis update for pi, stopping inference and returning record")
        return(record)
      } 
      
      if (log(runif(1)) < pTTree2-pTTree) {
        acceptNumPi <- acceptNumPi + 1 
        pi <- pi2
        pTTree <- pTTree2
      }       
    }
    
  }#End of main MCMC loop
  
  #close(pb)
  return(record)
}
