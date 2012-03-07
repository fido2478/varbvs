% [LNZ,ALPHA,MU,S] = VARBVS(X,Y,SIGMA,SA,LOGODDS) implements the
% fully-factorized variational approximation for Bayesian variable selection
% in linear regression. It finds the "best" fully-factorized variational
% approximation to the posterior distribution of the coefficients in a
% linear regression model of a continuous outcome (quantitiative trait),
% with spike and slab priors on the coefficients. By "best", we mean the
% approximating distribution that (locally) minimizes the Kullback-Leibler
% divergence between the approximating distribution and the exact posterior.
%
% The required inputs are as follows. Input X is an N x P matrix of
% observations about the variables (or features), where N is the number of
% samples, and P is the number of variables. Y is the vector of observations
% about the outcome; it is a vector of length N. Crucially, Y and X must be
% centered beforehand so that Y and each column of X has a mean of zero.
%
% Inputs SIGMA, SA and LOGODDS are the hyperparameters. SIGMA and SA are
% scalars. SIGMA specifies the variance of the residual, and SA*SIGMA is the
% prior variance of the additive effects. LOGODDS is the prior log-odds of
% inclusion for each variable. It is equal to LOGODDS = LOG(Q./(1-Q)), where
% Q is the prior probability that each variable is included in the linear
% model of Y. LOGODDS may either be a scalar, in which case all the
% variables have the same prior inclusion probability, or it may be a vector
% of length P.
%
% There are four outputs. Output LNZ is the variational estimate of the
% marginal log-likelihood given the hyperparameters SIGMA, SA and LOGODDS.
%
% Outputs ALPHA, MU and S are the parameters of the variational
% approximation, and the variational estimates of posterior quantites: under
% the variational approximation, the Kth regression coefficient is normal
% with probability ALPHA(K), and MU(K) and S(K) are the mean and variance of
% the coefficient given that it is included in the model.
%
% VARBVS(...,OPTIONS) overrides the default behaviour of the algorithm. Set
% OPTIONS.ALPHA and OPTIONS.MU to override the random initialization of
% variational parameters ALPHA and MU. Set OPTIONS.VERBOSE = FALSE to turn
% off reporting the algorithm's progress.
function [lnZ, alpha, mu, s] = varbvs (X, y, sigma, sa, logodds, options)

  % *** ADD COMMENTS HERE ***
  % Convergence criterion for coordinate ascent.
  tolerance = 1e-4;  

  % CHECK INPUTS.
  % Get the number of samples and variables.
  [n p] = size(X);

  % X must be single precision.
  if ~isa(X,'single')
    X = single(X);
  end

  % Y must be a double precision column vector of length N.
  y = double(y(:));
  if length(y) ~= n
    error('Data X and Y do not match.');
  end

  % SIGMA and SA must be double scalars.
  sigma = double(sigma);
  sa    = double(sa); 
  if ~(isscalar(sigma) & isscalar(sa))
    error('Inputs SIGMA and SA must be scalars.');
  end

  % LOGODDS must be a double precision column vector of length P.
  if isscalar(logodds)
    logodds = repmat(logodds,p,1);
  end
  logodds = double(logodds(:));
  if length(logodds) ~= p
    error(['LOGODDS must be a scalar or a vector of the same length as Y.');
  end

  % TAKE CARE OF OPTIONAL INPUTS.
  if ~exist('options')
    options = [];
  end

  % Set initial estimates of variational parameters.
  if isfield(options,'alpha') & isfield(options,'mu')
    alpha = options.alpha;
    mu    = options.mu;
  else
    
    % The variational parameters are initialized randomly so that exactly
    % one variable explains the outcome.
    alpha = rand(p,1);
    alpha = alpha / sum(alpha);
    mu    = randn(p,1);
  end

  % Determine whether to display the algorithm's progress.
  if isfield(options,'verbose')
    verbose = options.verbose;
  else
    verbose = true;
  end
  clear options
  
  % INITIAL STEPS.
  % Compute a few useful quantities. Here I calculate X'*Y as (Y'*X)' to
  % avoid storing the transpose of X, since X may be large.
  xy = double(y'*X)';
  d  = diagsq(X);
  Xr = double(X*(alpha.*mu));
  
  % Calculate the variance of the coefficients.
  s = sa*sigma./(sa*d + 1);
  
  % Repeat until convergence criterion is met.
  % *** FIX OUTPUTING OF PROGRESS ***
  lnZ  = -Inf;
  iter = 0;
  if verbose
    fprintf('iter           lnZ max chg #snp  beta\n');
  end
  while true

    % Go to the next iteration.
    iter = iter + 1;
    
    % Save the current variational parameters and lower bound.
    alpha0  = alpha;
    mu0     = mu;
    lnZ0    = lnZ;
    params0 = [ alpha; alpha .* mu ];

    % UPDATE VARIATIONAL APPROXIMATION.
    % Run a forward or backward pass of the coordinate ascent updates.
    if isodd(iter)
      snps = 1:p;
    else
      snps = p:-1:1;
    end
    [alpha mu Xr] = varbvsupdate(X,sigma,sa,logodds,xy,d,alpha,mu,Xr,snps);
    
    % COMPUTE VARIATIONAL LOWER BOUND.
    % Compute variational lower bound to the marginal log-likelihood.
    lnZ = intlinear(Xr,d,y,sigma,alpha,mu,s) ...
	  + intgamma(logodds,alpha) ...
	  + intklbeta(alpha,mu,s,sigma*sa);
    
    % Print the status of the algorithm and check the convergence criterion.
    % Convergence is reached when the maximum relative difference between
    % the parameters at two successive iterations is less than the specified
    % tolerance, or when the variational lower bound has decreased. I ignore
    % parameters that are very small.
    params = [ alpha; alpha .* mu ];
    is     = find(abs(params) > 1e-6);
    err    = relerr(params(is),params0(is));
    if verbose
      fprintf('%4d %+13.6e %0.1e %4d %0.3f\n',iter,lnZ,max(err),...
	      round(sum(alpha)),max(abs(alpha.*mu)));
    end
    if lnZ < lnZold
      alpha = alpha0;
      mu    = mu0;
      lnZ   = lnZold;
      break
    elseif max(err) < tolerance
      break
    end
  end