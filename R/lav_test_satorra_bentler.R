lav_test_satorra_bentler <- function(lavobject      = NULL,
                                     lavsamplestats = NULL,
                                     lavmodel       = NULL,
                                     lavoptions     = NULL,
                                     TEST.unscaled  = NULL,
                                     E.inv          = NULL,
                                     Delta          = NULL,
                                     WLS.V          = NULL,
                                     Gamma          = NULL,
                                     test           = "satorra.bentler",
                                     mimic          = "lavaan",
                                     method         = "default") {

    TEST <- list()

    if(!is.null(lavobject)) {
        lavsamplestats <- lavobject@SampleStats
        lavmodel       <- lavobject@Model
        lavoptions     <- lavobject@Options
        lavpartable    <- lavobject@ParTable
        TEST$standard  <- lavobject@Fit@test[[1]]
    }

    # check test
    if(!all(test %in% c("satorra.bentler",
                        "scaled.shifted",
                        "mean.var.adjusted"))) {
        warning("lavaan WARNING: test must be one of `satorra.bentler', `scaled.shifted' or `mean.var.adjusted'; will use `satorra.bentler' only")
        test <- "satorra.benter"
    }

    # check method
    if(method == "default") {
        method <- "original"
    } else if(!all(method %in% c("original", "orthogonal.complement", 
                                 "ABA"))) {
        warning("lavaan WARNING: method must be one of `original', `orthogonal.complement'; will use `original'")
        method <- "original"
    }

    # do we have E.inv, Delta, WLS.V?
    if(is.null(E.inv) || is.null(Delta) || is.null(WLS.V)) {
        if(mimic == "Mplus" && lavoptions$estimator == "ML") {
            E <- lav_model_information_expected_MLM(lavmodel = lavmodel,
                     augmented = FALSE, inverted = FALSE,
                     lavsamplestats=lavsamplestats, extra = TRUE)
        } else {
            E <- lav_model_information_expected(lavmodel = lavmodel,
                     lavsamplestats = lavsamplestats, lavdata = lavdata,
                     estimator = lavoptions$estimator, extra = TRUE)
        }
        E.inv <- try(lav_model_information_augment_invert(lavmodel,
                         information = E, inverted = TRUE), silent=TRUE)
        if(inherits(E.inv, "try-error")) {
            TEST <- list(test=test, stat=as.numeric(NA),
                stat.group=rep(as.numeric(NA), lavsamplestats@ngroups),
                df=df, refdistr=refdistr, pvalue=as.numeric(NA),
                scaling.factor=as.numeric(NA))
            warning("lavaan WARNING: could not invert information matrix\n")
            return(TEST)
        }
        Delta <- attr(E, "Delta")
        WLS.V <- attr(E, "WLS.V")
    }

    # Gamma
    if(is.null(Gamma)) {
        Gamma <- lavsamplestats@NACOV
    }

    # ngroups
    ngroups <- lavsamplestats@ngroups

    # mean and variance adjusted?
    Satterthwaite <- FALSE
    if(any(test %in% c("mean.var.adjusted", "scaled.shifted"))) {
        Satterthwaite <- TRUE
    }

    if(method == "original") {
        out <- lav_test_satorra_bentler_trace_original(Gamma = Gamma,
                   Delta = Delta, WLS.V = WLS.V, E.inv = E.inv, 
                   ngroups = ngroups, nobs = lavsamplestats@nobs, 
                   ntotal = lavsamplestats@ntotal,
                   Satterthwaite = Satterthwaite)
    } else if(method == "orthogonal.complement") {
        out <- lav_test_satorra_bentler_trace_complement(Gamma = Gamma,
                   Delta = Delta, WLS.V = WLS.V, lavmodel = lavmodel,
                   ngroups = ngroups, nobs = lavsamplestats@nobs,
                   ntotal = lavsamplestats@ntotal,
                   Satterthwaite = Satterthwaite)
    } else if(method == "ABA") {
        out <- lav_test_satorra_bentler_trace_ABA(Gamma = Gamma,
                   Delta = Delta, WLS.V = WLS.V, E.inv = E.inv,
                   ngroups = ngroups, nobs = lavsamplestats@nobs,
                   ntotal = lavsamplestats@ntotal,
                   Satterthwaite = Satterthwaite)
    } else {
        stop("lavaan ERROR: method `", method, "' not supported")
    }
    trace.UGamma  <- out$trace.UGamma
    trace.UGamma2 <- out$trace.UGamma2


    if("satorra.bentler" %in% test) {
        # same df
        df.scaled <- TEST$standard$df

        # scaling factor
        scaling.factor <- trace.UGamma/df.scaled
        if(scaling.factor < 0) scaling.factor <- as.numeric(NA)

        # scaled test statistic per group
        stat.group <- TEST$standard$stat.group / scaling.factor

        # scaled test statistic global
        stat <- sum(stat.group)

        TEST$satorra.benter <-
            list(test            = "satorra.bentler",
                 stat            = stat,
                 stat.group      = stat.group,
                 df              = df.scaled,
                 pvalue          = 1 - pchisq(stat, df.scaled),
                 trace.UGamma    = trace.UGamma,
                 scaling.factor  = scaling.factor)
    }

    if("mean.var.adjusted" %in% test) {
        if(mimic == "Mplus") {
            df.scaled <- floor(trace.UGamma^2/trace.UGamma2 + 0.5)
        } else {
            # more precise, fractional df
            df.scaled <- trace.UGamma^2 / trace.UGamma2
        }

        # scaling factor
        scaling.factor <- trace.UGamma/df.scaled
        if(scaling.factor < 0) scaling.factor <- as.numeric(NA)

        # scaled test statistic per group
        stat.group <- TEST$standard$stat.group / scaling.factor

        # scaled test statistic global
        stat <- sum(stat.group)

        TEST$mean.var.adjusted <-
            list(test            = "mean.var.adjusted",
                 stat            = stat,
                 stat.group      = stat.group,
                 df              = df.scaled,
                 pvalue          = 1 - pchisq(stat, df.scaled),
                 trace.UGamma    = trace.UGamma,
                 trace.UGamma2   = trace.UGamma2,
                 scaling.factor  = scaling.factor)
    }

    if("scaled.shifted" %in% test) {
        # this is the T3 statistic as used by Mplus 6 and higher
        # see 'Simple Second Order Chi-Square Correction' 2010
        # www.statmodel.com

        # however, for multiple groups, Mplus reports something else
        # YR. 30 Aug 2012 -- after much trial and error, it turns out
        # that the shift-parameter (b) is weighted (while a is not)??
        # however, the chisq.square per group are different; only
        # the sum seems ok??

        # same df
        df.scaled <- TEST$standard$df

        # scaling factor
        fg <- unlist(lavsamplestats@nobs)/lavsamplestats@ntotal
        a <- sqrt(df.scaled/trace.UGamma2)
        shift.parameter <- fg * (df.scaled - a*trace.UGamma)
        scaling.factor  <- 1/a
        if(scaling.factor < 0) scaling.factor <- as.numeric(NA)

        # # scaled test statistic per group
        stat.group <- (TEST$standard$stat.group * a + shift.parameter)

        # scaled test statistic global
        stat <- sum(stat.group)
        
        TEST$scaled.shifted <-
            list(test            = "scaled.shifted",
                 stat            = stat,
                 stat.group      = stat.group,
                 df              = df.scaled,
                 pvalue          = 1 - pchisq(stat, df.scaled),
                 trace.UGamma    = trace.UGamma,
                 trace.UGamma2   = trace.UGamma2,
                 scaling.factor  = scaling.factor,
                 shift.parameter = shift.parameter)
    }

    TEST
}

# using the `classical' formula
# UG = Gamma * [V - V Delta E.inv Delta' V']
lav_test_satorra_bentler_trace_original <- function(Gamma         = NULL,
                                                    Delta         = NULL,
                                                    WLS.V         = NULL,
                                                    E.inv         = NULL,
                                                    ngroups       = NULL,
                                                    nobs          = NULL,
                                                    ntotal        = NULL,
                                                    Satterthwaite = FALSE) {
 
    # trace of UGamma per group
    trace.UGamma  <- trace.UGamma2 <- rep(as.numeric(NA), ngroups)

    # per group
    for(g in 1:ngroups) {
        fg <- nobs[[g]]/ntotal
        Gamma.g <- Gamma[[g]] / fg  ## ?? check this
        Delta.g <- Delta[[g]]
        WLS.Vg  <- WLS.V[[g]] * fg

        U <- (WLS.Vg - WLS.Vg %*% Delta[[g]] %*% E.inv %*% 
                                t(Delta[[g]]) %*% WLS.Vg) 
        trace.UGamma[g] <- sum(U * Gamma.g)

        if(Satterthwaite) {
            UG <- U %*% Gamma.g
            trace.UGamma2[g] <- sum(UG * t(UG))
        }
    }

    # sum over groups
    trace.UGamma <- sum(trace.UGamma)
    trace.UGamma2 <- sum(trace.UGamma2)

    list(trace.UGamma = trace.UGamma, trace.UGamma2 = trace.UGamma2)
}

# using the orthogonal complement of Delta: Delta.c
# UG = [ (Delta.c' W Delta.c)^{-1} (Delta.c' Gamma Delta.c)
lav_test_satorra_bentler_trace_complement <- function(Gamma         = NULL,
                                                      Delta         = NULL,
                                                      WLS.V         = NULL,
                                                      lavmodel      = NULL,
                                                      ngroups       = NULL,
                                                      nobs          = NULL,
                                                      ntotal        = NULL,
                                                      Satterthwaite = FALSE) {

    # trace of UGamma per group
    trace.UGamma  <- trace.UGamma2 <- rep(as.numeric(NA), ngroups)

    # per group
    for(g in 1:ngroups) {
        fg <- nobs[[g]]/ntotal
        Gamma.g <- Gamma[[g]] / fg  ## ?? check this
        Delta.g <- Delta[[g]]
        WLS.Vg  <- WLS.V[[g]] * fg

        # handle equality constraints
        if(lavmodel@eq.constraints) {
            Delta.g <- Delta.g %*% lavmodel@eq.constraints.K
        }

        # orthogonal complement of Delta.g
        Delta.c <- lav_matrix_orthogonal_complement(Delta.g)

        ### FIXME: compute WLS.W directly, instead of using solve(WLS.V)

        tmp1 <- solve(t(Delta.c) %*% solve(WLS.Vg) %*% Delta.c)
        tmp2 <- t(Delta.c) %*% Gamma.g %*% Delta.c

        trace.UGamma[g] <- sum(tmp1 * tmp2)
        if(Satterthwaite) {
            UG <- tmp1 %*% tmp2
            trace.UGamma2[g] <- sum(UG * t(UG))
        }
    }

    # sum over groups
    trace.UGamma <- sum(trace.UGamma)
    trace.UGamma2 <- sum(trace.UGamma2)

    list(trace.UGamma = trace.UGamma, trace.UGamma2 = trace.UGamma2)
}

# using the ABA form
# UG = Gamma %*% [V - V %*% Delta %*% E.inv %*% tDelta %*% V]
#    = Gamma %*% V  - Gamma %*% V %*% Delta %*% E.inv %*% tDelta %*% V
#    = Gamma %*% A1 - Gamma %*% A1 %*% Delta %*% E.inv %*% tDelta %*% A1
# (B1 = A1 %*% Gamma %*% A1)
#    = B1 %*% A1.inv - B1 %*% A1.inv %*% Delta %*% E.inv %*% tDelta %*% A1
#    
# if only the trace is needed, we can use reduce the rhs (after the minus)
# to B1 %*% Delta %*% E.inv %*% tDelta (eliminating A1 and A1.inv)

# we write it like this to allow for fixed.x covariates which affect A1
# and B1
lav_test_satorra_bentler_trace_ABA <- function(Gamma         = NULL,
                                               Delta         = NULL,
                                               WLS.V         = NULL,
                                               E.inv         = NULL,
                                               ngroups       = NULL,
                                               nobs          = NULL,
                                               ntotal        = NULL,
                                               Satterthwaite = FALSE) {

    # trace of UGamma per group
    trace.UGamma  <- trace.UGamma2 <- rep(as.numeric(NA), ngroups)

    # per group
    for(g in 1:ngroups) {
        fg <- nobs[[g]]/ntotal
        Gamma.g <- Gamma[[g]] / fg  ## ?? check this
        Delta.g <- Delta[[g]]
        WLS.Vg  <- WLS.V[[g]] * fg

        # diagonal WLS.V? we check for this since 0.5-17
        diagonal <- FALSE
        if(is.matrix(WLS.V[[g]])) {
            A1 <- WLS.V[[g]] * fg
            B1 <- A1 %*% Gamma.g %*% A1
        } else {
            diagonal <- TRUE
            a1 <- WLS.V[[g]] * fg # numeric vector!
            B1 <- Gamma.g * tcrossprod(a1)
        }

        # mask independent 'fixed-x' variables
        # note: this only affects the saturated H1 model
        #if(length(x.idx[[g]]) > 0L) {
        #    nvar <- ncol(lavsamplestats@cov[[g]])
        #    idx <- eliminate.pstar.idx(nvar=nvar, el.idx=x.idx[[g]],
        #                               meanstructure=TRUE, type="all")
        #    if(diagonal) {
        #        a1 <- a1[idx]
        #    } else {
        #        A1 <- A1[idx,idx]
        #    }
        #    B1      <- B1[idx,idx]
        #    Delta.g <- Delta.g[idx,]
        #}

        if(diagonal) {
            UG <- t((1/a1) * B1) - (B1 %*% Delta.g %*% tcrossprod(E.inv, Delta.g))
        } else {
            A1.inv <- solve(A1)
            UG <- (B1 %*% A1.inv) - (B1 %*% Delta.g %*% tcrossprod(E.inv, Delta.g))
        }

        trace.UGamma[g] <- sum(diag(UG))
        if(Satterthwaite) {
            trace.UGamma2[g] <- sum(UG * t(UG))
        }
    }

    # sum over groups
    trace.UGamma <- sum(trace.UGamma)
    trace.UGamma2 <- sum(trace.UGamma2)

    list(trace.UGamma = trace.UGamma, trace.UGamma2 = trace.UGamma2)
}

