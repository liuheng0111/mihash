function val_id = val_adapt(alpha_p, beta_p, stepsize_p, val_dir, val_size, varargin)
% varargin can contain any parameters excluding method specific ones
if isempty(val_dir)
	val_dir = '/research/object_detection/cachedir/online-hashing/adapt/val_diaries';
	if ~exist(val_dir, 'dir')
		unix(['mkdir ' val_dir]);
		unix(['chmod g+w ' val_dir]);
		unix(['chmod o-w ' val_dir]);
	end
end
vrg = varargin{1};
dataset = vrg{2};
val_id = sprintf('%s/VAL-Adapt-%s-VS%d-A%s-B%s-SS%s', val_dir, dataset, val_size, ...
	strjoin_fe(strread(num2str(alpha_p),'%s'),'_'), ...
		strjoin_fe(strread(num2str(beta_p),'%s'),'_'), ...
			strjoin_fe(strread(num2str(stepsize_p),'%s'),'_'));
fclose('all');

[val_fid, msg] = fopen([val_id '.txt'],'w+');
if val_fid == -1
     error(msg);
end
% get demo_adapthash input
for a=1:length(alpha_p)
	for b=1:length(beta_p)
		for s=1:length(stepsize_p)
			vrg{end+1} = 'alpha';
			vrg{end+1} = alpha_p(a);
			vrg{end+1} = 'beta';
			vrg{end+1} = beta_p(b);
			vrg{end+1} = 'stepsize';
			vrg{end+1} = stepsize_p(s);
			vrg{end+1} = 'val_size';
			vrg{end+1} = val_size;
			varargin_ = vrg;
			[resfn, dp] = demo_adapthash(varargin_{:});
			r = load(resfn);
			fprintf(val_fid, 'mean mAP: %g alpha: %d, beta: %d stepsize :%d diary path: %s\n', ...
                    mean(r.res(:,end)), alpha_p(a), beta_p(b), stepsize_p(s), dp);
			clear r
			vrg = varargin{1};
		end
	end
end
fclose(val_fid);
end
