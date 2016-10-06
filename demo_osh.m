function resfn = demo_osh(ftype, dataset, nbits, varargin)
% PARAMS
%  ftype (string) from {'gist', 'cnn'}
%  dataset (string) from {'cifar', 'sun','nus'}
%  nbits (integer) is length of binary code
%  varargin: see get_opts.m for details

% get OSH-specific fields first
ip = inputParser;
ip.addParamValue('stepsize', 0.1, @isscalar);
ip.addParamValue('SGDBoost', 0, @isscalar);
for i = 1:2:length(varargin)-1
    % only parse defined fields, ignore others
    try
        ip.parse(varargin{i}, varargin{i+1});
    end
end
opts = ip.Results;
opts.identifier = sprintf('B%dS%g', opts.SGDBoost, opts.stepsize);
opts.localid = '';

% get generic fields
opts = get_opts(opts, ftype, dataset, nbits, varargin{:});  % set parameters

% run demo
resfn = demo(opts, @train_osh, @test_osh);
diary('off');
end
