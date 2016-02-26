function train_osh_rs(traingist, trainlabels, opts)
	% online supervised hashing
	% regularization term defined on reservoir samples
	
	train_time  = zeros(1, opts.ntrials);
	update_time = zeros(1, opts.ntrials);
	bit_flips   = zeros(1, opts.ntrials);
	parfor t = 1:opts.ntrials
		myLogInfo('%s: random trial %d', opts.identifier, t);
		[train_time(t), update_time(t), bit_flips(t)] = train_sgd_rs(...
			traingist, trainlabels, opts, t);
	end
	myLogInfo('Training time (total): %.2f +/- %.2f', mean(train_time), std(train_time));
	if strcmp(opts.mapping, 'smooth')
		myLogInfo('    Bit flips (total): %.4g +/- %.4g', mean(bit_flips), std(bit_flips));
	end
end

% -------------------------------------------------------------
function [train_time, update_time, bitflips] = train_sgd_rs(...
		traingist, trainlabels, opts, trialNo)
	% SGD with reservoir regularizer
	prefix = sprintf('%s/trial%d', opts.expdir, trialNo);
	noexist = 0;
	for i = 1:floor(opts.noTrainingPoints/opts.test_interval)
		if ~exist(sprintf('%s_iter%d.mat', prefix, i), 'file')
			noexist = noexist + 1;
		end
	end
	if noexist == 0 && exist([prefix '.mat'], 'file')
		myLogInfo('Trial %d already done.', trialNo); 
		load([prefix '.mat']);
		return;
	end

	% randomly generate candidate codewords, store in M2
	bigM = 10000;
	M2   = zeros(bigM, opts.nbits);
	for t = 1:opts.nbits
		r = ones(bigM, 1);
		while (abs(sum(r)) == bigM)
			r = 2*randi([0,1], bigM, 1)-1;
		end
		M2(:, t) = r;
	end
	clear r

	% initialize with LSH
	d = size(traingist, 2);
	W = randn(d, opts.nbits);
	W = W ./ repmat(diag(sqrt(W'*W))',d,1);
	Y = [];  % the indexing structure

	bitflips = 0;
	train_time = 0;
	update_time = 0;

	% reservoir sampling
	ntrain_all     = size(traingist, 1);
	reservoir_size = opts.samplesize; %ceil(opts.sampleratio*ntrain_all);
	samplegist     = zeros(reservoir_size, size(traingist, 2));
	samplelabel    = zeros(reservoir_size, 1);
	Yres           = [];  % mapped binary codes for the reservoir

	i_ecoc = 1;
	seenLabels = [];
	for i = 1:opts.noTrainingPoints
		t_ = tic;
		% new training point
		spoint = traingist(i, :);
		slabel = trainlabels(i);

		% check whether it exists in the "seen class labels" vector
		islabel = find(seenLabels == slabel);
		if isempty(islabel)
			if isempty(seenLabels)
				% does not exist, create a binary code for M
				seenLabels = slabel;
				M = M2(i_ecoc, :);
				i_ecoc = i_ecoc + 1;
			else
				% append codeword to ECOC matrix
				seenLabels = [seenLabels; slabel];
				M = [M; M2(i_ecoc,:)];
				i_ecoc = i_ecoc +1;
			end
		end
		islabel = find(seenLabels == slabel);
		target_code = M(islabel, :);

		% reservoir update (based on random sort)
		priority_queue = zeros(1, reservoir_size);
		if i <= reservoir_size
			samplegist(i, :)  = spoint;
			samplelabel(i)    = slabel;
			priority_queue(i) = rand;
		else
			% pop max from priority queue
			[maxval, maxind] = max(priority_queue);
			r = rand;
			if maxval > r
				% push into priority queue
				priority_queue(maxind) = r;
				samplegist(maxind, :)  = spoint;
				samplelabel(maxind)    = slabel;
			end
		end
		% compute binary codes for the reservoir
		if isempty(Yres)
			Yres = build_hash_table(W, samplegist, samplelabel, seenLabels, M, opts)';
		else
			Ynew = build_hash_table(W, samplegist, samplelabel, seenLabels, M, opts)';
			bitdiff = (Yres ~= Ynew);
			bitflips = bitflips + sum(bitdiff(:));
			Yres = Ynew;
		end

		% hash function update
		if opts.SGDBoost == 0
			for j = 1:opts.nbits
				% gradient descent on fist term: loss
				% (try to fit to target code)
				if target_code(j)*W(:,j)'*spoint' <= 1
					W(:,j) = W(:,j) + opts.stepsize * target_code(j)*spoint';
				end
				% GD on second term: reservoir regularizer
				% (try to fit to previous mapped codes)
				%if i > reservoir_size
				rstep = opts.stepsize * opts.lambda / reservoir_size;
				for r = 1:min(reservoir_size, i)
					rpoint = samplegist(r, :);
					if Yres(r, j)*W(:, j)'*rpoint' <= 1
						W(:,j) = W(:,j) + rstep * Yres(r, j) * rpoint';
					end
				end
				%end
			end
		else
			% TODO
			for j = 1:opts.nbits
				if j ~= 1
					c1 = exp(-(target_code(1:j-1)*(W(:,1:j-1)'*spoint')));
				else
					c1 = 1;
				end
				W(:,j) = W(:,j) - opts.stepsize * ...
					c1 * exp(-target_code(j)*W(:,j)'*spoint')*-target_code(j)*spoint';
			end
		end
		train_time = train_time + toc(t_);

		% hash index update
		if strcmp(opts.mapping, 'smooth') && ~mod(i, opts.update_interval)
			t_ = tic;
			if isempty(Y)
				Y = build_hash_table(W, traingist, trainlabels, seenLabels, M, opts);
			else
				Ynew = build_hash_table(W, traingist, trainlabels, seenLabels, M, opts);
				bitdiff = (Y ~= Ynew);
				bitflips = bitflips + sum(bitdiff(:));
				Y = Ynew;
			end
			update_time = update_time + toc(t_);
		end

		% cache intermediate model to disk
		if ~mod(i, opts.test_interval)
			if isempty(Y)
				Y = build_hash_table(W, traingist, trainlabels, seenLabels, M, opts);
			end
			savefile = sprintf('%s_iter%d.mat', prefix, i);
			save(savefile, 'W', 'Y', 'bitflips', 'train_time', 'update_time');
			unix(['chmod o-w ' savefile]);  % matlab permission bug
		end
	end % end for

	% populate hash table
	t_ = tic;
	Y = build_hash_table(W, traingist, trainlabels, seenLabels, M, opts);
	update_time = update_time + toc(t_);
	myLogInfo('Trial %02d. SGD+reservoir: %.2f sec, Hashtable update: %.2f sec', ...
		trialNo, train_time, update_time);

	% save final model, etc
	save([prefix '.mat'], 'W', 'Y', 'bitflips', 'train_time', 'update_time');
	unix(['chmod o-w ' prefix '.mat']);  % matlab permission bug
end
