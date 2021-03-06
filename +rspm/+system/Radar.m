% A class representing a Radar system
%
% TODO:
% - Allow the user to create a pulse train with multiple types of waveforms
% - Add multistatic capabilities
%
% Blame: Shane Flandermeyer
classdef Radar < AbstractRFSystem
  
  %% Private properties
  properties (Access = private)
    % List of parameters that should be updated when we change the scale
    % from linear to dB or vice versa
    power_list = {'loss_system','noise_fig'};
  end
  
  % Members exposed to the outside world
  properties (Dependent)
    antenna;          % AbstractAntenna object
    waveform;         % Waveform object
    prf;              % Pulse repetition frequency (Hz)
    pri;              % Pulse repetition interval (s)
    num_pulses;       % Number of pulses in a CPI
    range_unambig;    % Unambiguous range (m)
    velocity_unambig; % Unambiguous velocity (m/s)
    doppler_unambig;  % Unambiguous doppler frequency (Hz)
    range_resolution; % Range resolution (m)
    range_horizon;    % Range to the horizon
  end
  
  % Internal class data
  properties (Access = protected)
    d_antenna;
    d_waveform;
    d_prf;
    d_pri;
    d_num_pulses;
  end
  
  %% Public Methods
  methods
    
    function Ru = SMICovariance(obj,clutter,jammers,num_snapshots)
      % Estimate the Interference covariane matrix for the given
      % clutter and jammer objects using num_snapshots space-time
      % snapshots of data. This function assumes the system noise and
      % jammer amplitude variations over time follow a Gaussian
      % distribution with amplitude proportional to the noise power
      % and/or JNR. The clutter amplitude of each patch is assumed to
      % be Gaussian distributed, but constant for each element/pulse
      
      
      % Perform all calculations in linear units and with radian
      % angles
      radar = copy(obj);
      clutter = copy(clutter);
      jammers = copy(jammers);
      radar.scale = 'Linear';
      [clutter.scale] = deal('Linear');
      [clutter.angle_unit] = deal('Radians');
      [jammers.scale] = deal('Linear');
      [jammers.angle_unit] = deal('Radians');
      
      M = radar.num_pulses; % Number of pulses
      N = radar.antenna.num_elements; % Number of antenna elements
      training_samps = zeros(M*N,num_snapshots);
      
      % Get the spatial steering vector for each jammer. The jammers
      % are assumed to be temporally uncorrelated, so I'm calculating
      % the temporal steering vector in the loop below
      freq_spatial_jam = radar.antenna.spacing_element/radar.wavelength*...
        cos([jammers.elevation]).*sin([jammers.azimuth]);
      Aj = radar.antenna.spatialSteeringVector(freq_spatial_jam);
      % Get the space-time steering vector for each clutter patch
      [~,Vc] = clutter.covariance(radar);
      % Total jammer contribution to training snapshot
      jam = zeros(M*N,1);
      jnr = jammers.JNR(radar); % Jammer to noise ratio
      cnr = clutter.CNR(radar); % Clutter to noise ratio
      % TODO: Make a method to generate jammer/clutter samples over
      % time instead of doing it here. That would give the user more
      % control over the distribution
      for ii = 1 : num_snapshots
        % Clutter Contributions
        clut = (sqrt(radar.power_noise)/2*cnr.').*...
          (rand(1,clutter.num_patches) + 1i*randn(1,clutter.num_patches));
        clut = repmat(clut,M*N,1);
        clut = sum(clut.*Vc,2);
        
        % Noise contributions
        noise = (sqrt(radar.power_noise)/2)*(randn(M*N,1)+1i*randn(M*N,1));
        
        % Jammer contributions
        for kk = 1 : length(jammers)
          % Time-dependent jammer amplitude
          jam_temporal = (sqrt(radar.power_noise)/2*jnr(kk))*...
            (randn(M,1) + 1i*randn(M,1));
          jam = jam + kron(jam_temporal, Aj(:,kk));
        end
        
        % Total interference snapshot
        training_samps(:,ii) = noise + jam + clut;
      end
      % Estimate the sample covariance matrix from the training data with
      % Ward eq. (129), but subtract the mean
      mean = 1/num_snapshots*sum(training_samps,2);
      Ru = 1/num_snapshots*(training_samps*training_samps') - mean;
      
    end
    
    function v = spaceTimeSteeringVector(obj,freq_spatial,freq_doppler)
      % Compute the space-time steering vector to the given spatial and
      % UNNORMALIZED doppler frequency (Hz)
      
      if numel(freq_spatial) ~= numel(freq_doppler)
        error("Inputs must be the same size")
      end
      %
      %       if numel(freq_spatial) > 1 ||numel(freq_doppler) > 1
      %         error('This function currently only supports scalar inputs')
      %       end
      %
      % Calculate the spatial steering vector
      if ~isa(obj.antenna,'AbstractAntennaArray')
        % If the antenna is not an array, there is no steering
        a = 1;
      else
        a = obj.antenna.spatialSteeringVector(freq_spatial);
      end
      
      % Calculate the temporal steering vector
      b = obj.temporalSteeringVector(freq_doppler);
      
      % Calculate the space-time steering vector
      v = zeros(size(a,1)*size(b,1),length(freq_spatial));
      for ii = 1:length(freq_spatial)
        v(:,ii) = kron(b(:,ii),a(:,ii));
      end
      
    end
    
    function b = temporalSteeringVector(obj,freq_doppler)
      % Computes the temporal steering vector to an UNNORMALIZED doppler
      % frequency in Hz. If the input is a vector of size L, this function
      % returns an M x L matrix, where M is the number of pulses per CPI
      % and each column in the matrix corresponds to a doppler shift from
      % the input
      
      % If the input is a column vector, make it a row vector to maintain
      % the output dimensions specified above
      if ~isscalar(freq_doppler) && iscolumn(freq_doppler)
        freq_doppler = freq_doppler.';
      end
      
      if numel(freq_doppler) == 1 % Scalar case
        b = exp(1i*2*pi*freq_doppler/obj.prf*(0:obj.num_pulses-1)');
      else % Vector case
        % Set up problem dimensions so that we can use a Hadamard product
        % instead of a loop
        M = repmat((0:obj.num_pulses-1)',1,numel(freq_doppler));
        freq_doppler = repmat(freq_doppler,obj.num_pulses,1);
        b = exp(1i*2*pi*freq_doppler/obj.prf.*M);
      end
      
    end
    
    function beta = clutterBeta(obj)
      
      if ~isa(obj.antenna,'AbstractAntennaArray')
        error('Antenna must be an array (for now)')
      end
      
      beta = 2*norm(obj.velocity)*obj.pri/obj.antenna.spacing_element;
    end
    
    function rank = clutterRank(obj)
      % Calculates the clutter rank according to Brennan's rule.
      % That is, rc = round(N + (M-1)beta), where N is the number of antenna
      % array elements, M is the number of pulses per CPI, and beta is the
      % number of half interelement spacings traversed by the platform
      % during a single PRI
      
      if ~isa(obj.antenna,'AbstractAntennaArray')
        error('Antenna must be an array (for now)')
      end
      beta = obj.clutterBeta;
      rank = round(obj.antenna.num_elements + (obj.num_pulses-1)*beta);
      
    end
    
    function range = measuredRange(obj,targets)
      % For each target in the list, calculate the range measured by the
      % angle_quantities, accounting for range ambiguities;
      range = obj.trueRange(targets);
      for ii = 1:length(range)
        % Get the projection of the position vector onto the mainbeam pointing
        % vector
        range(ii) = mod(range(ii),obj.range_unambig);
      end
    end
    
    function range = trueRange(obj,targets)
      % For each target in the list, calculate the true range of the target from
      % the radar
      range = vecnorm([targets(:).position]-obj.position)';
    end % trueRange()
    
    function doppler = measuredDoppler(obj,targets)
      if ~isa(targets,'AbstractTarget')
        error('Function only supports target objects')
      end
      % Calculate the measured doppler shift of each target in the list,
      % accounting for ambiguities
      doppler = zeros(numel(targets),1); % Pre-allocate
      for ii = 1 : length(doppler)
        % Calculate the shift that would be measured with no ambiguities.
        % NOTE: We define negative doppler as moving towards the radar, so there
        % is a sign change.
        position_vec = targets(ii).position - obj.position;
        position_vec = position_vec / norm(position_vec);
        true_doppler = -dot(targets(ii).velocity,position_vec)*...
          2/obj.antenna.wavelength;
        
        if (abs(true_doppler) < obj.prf/2)
          % Shift can be measured unambiguously, send it straight to the
          % output
          doppler(ii) = true_doppler;
        elseif mod(true_doppler,obj.prf) < obj.prf/2
          % Aliased doppler is within the measurable range; output it
          aliased_doppler = mod(true_doppler,obj.prf);
          doppler(ii) = aliased_doppler;
        elseif mod(true_doppler,obj.prf) > obj.prf/2
          % Aliased doppler is still ambiguous. Shift it into the measurable
          % range
          aliased_doppler = mod(true_doppler,obj.prf);
          doppler(ii) = aliased_doppler-obj.prf;
        end % if
      end % for
    end
    
    function velocity = measuredVelocity(obj,targets)
      % Calculate the velocity measured by the radar for each target in the
      % list. In this case, it's easier to find measured doppler and convert
      % from there
      
      doppler = obj.measuredDoppler(targets);
      velocity = doppler*obj.antenna.wavelength/2;
      
    end
    
    function phase = roundTripPhase(obj,targets)
      
      % Calculate the constant round-trip phase term for each target in the list
      phase = -4*pi*obj.measuredRange(targets)/obj.antenna.wavelength;
      phase = mod(phase,2*pi);
      
    end
    
    function power = receivedPower(obj,targets)
      % Calculates the received power for the list of targets from the RRE.
      % For now, assuming monostatic configuration (G_t = G_r)
      
      if ~isa(obj.antenna,'AbstractAntennaArray')
        % TODO: Make this an abstract method in the antenna classes
        error('Calculation only holds for Antenna Array objects')
      end
      
      radar = copy(obj);
      radar.scale = 'Linear';
      radar.antenna.angle_unit = 'Radians';
      
      % Get the azimuth and elevation of the targets
      pos_matrix = [targets.position]';
      [az,el] = cart2sph(pos_matrix(:,1),pos_matrix(:,2),pos_matrix(:,3));
      % Get the antenna gain in the azimuth/elevation of the targets. Also
      % convert to linear units if we're working in dB
      G = radar.antenna.gain_element*radar.antenna.elements(1,1).normPowerGain(az,el);
      % Get the target ranges as seen by the radar
      ranges = radar.trueRange(targets);
      % Calculate the power from the RRE for each target
      power = radar.power_tx*G.^2*radar.wavelength^2.*...
        [targets(:).rcs]'./((4*pi)^3*radar.loss_system*ranges.^4);
      
      % Convert back to dB if necessary
      if strcmpi(obj.scale,'dB')
        power = 10*log10(power);
      end
      
    end
    
    function pulses = pulseBurstWaveform(obj)
      % Returns an LM x 1 pulse train, where L is the number of fast time
      % samples of the waveform and M is the number of pulses to be
      % transmitted
      
      % Pad pulse to the PRI length
      num_zeros = (obj.pri-obj.waveform.pulse_width)*obj.waveform.samp_rate;
      padded_pulse = [obj.waveform.data;zeros(num_zeros,1)];
      % Stack num_pulses padded pulses on top of each other
      pulses = repmat(padded_pulse,obj.num_pulses,1);
      
    end
    
    function mf = pulseBurstMatchedFilter(obj)
      
      % Returns an LM x 1 pulse train containing M copies of the length-L
      % matched filter vector
      mf = flipud(conj(obj.pulseBurstWaveform()));
      
    end
    
    function pulses = pulseMatrix(obj)
      
      % Returns an L x M pulse train, where L is the number of fast time
      % samples of the waveform and M is the number of pulses to be
      % transmitted
      
      % Pad pulse to the PRI length
      num_zeros = (obj.pri-obj.waveform.pulse_width)*obj.waveform.samp_rate;
      padded_pulse = [obj.waveform.data;zeros(round(num_zeros),1)];
      % Stack num_pulses padded pulses on top of each other
      pulses = repmat(padded_pulse,1,obj.num_pulses);
      
    end
    
    function out = simulateTargets(obj,targets,data)
      
      % Simulate reflections from each target in the list on the given
      % input data, including a time delay, amplitude scaling, and doppler
      % shift.
      %
      % INPUTS:
      %  - targets: The list of target objects
      %  - data: The data in which target responses are injected
      %
      % OUTPUT: The scaled and shifted target response
      
      radar = copy(obj);
      radar.scale = 'Linear';
      
      % Simulate the response of each target in the list on the input pulses.
      % This response includes the range-dependent target delay, the target
      % amplitude (from the RRE), and the target doppler shift
      
      % Input is a vector. Reshape to a matrix to do the calculations
      was_vector = false;
      if size(data,2) == 1
        data = reshape(data,floor(length(data)/radar.num_pulses),radar.num_pulses);
        was_vector = true;
      end
      
      out = zeros(size(data)); % Pre-allocate the output matrix
      % Loop through all PRIs in the input data and create a scaled and
      % shifted copy for each target. The output for each PRI is the
      % superposition of these pulses
      for ii = 1:radar.num_pulses
        % The true range of each target (used to ensure we don't include
        % ambiguous target returns before the pulse is actually received
        true_ranges = radar.trueRange(targets);
        % The range of each target as seen from the radar
        ranges = radar.measuredRange(targets);
        % The possibly ambiguous sample delays of each target
        delays = (2*ranges/radar.const.c)*radar.waveform.samp_rate;
        % The doppler shifts and amplitude for each target
        dopp_shifts = exp(1i*2*pi*radar.measuredDoppler(targets)*radar.pri*ii);
        amplitude_scaling = sqrt(radar.receivedPower(targets));
        for jj = 1:length(targets)
          % If we have not been transmitting long enough to see a target, its
          % return should not be added into the received signal until we have
          % listened long enough to see it. For example, if a target is at
          % 1.5*r_unambig, it will not be visible until the second pulse.
          if true_ranges(jj) < radar.range_unambig*ii
            % Delay the sequence
            target_return = Radar.delaySequence(data(:,ii),delays(jj));
            % Scale the sequence by the RRE and doppler shift it according to
            % the target doppler
            target_return = target_return*dopp_shifts(jj)*amplitude_scaling(jj);
            % Add the result to the output of the current pulse
            out(:,ii) = out(:,ii) + target_return;
            
            % Shift the target to its position for the next PRI
            targets(jj).position = targets(jj).position + ...
              targets(jj).velocity*radar.pri;
          end
        end
      end
      
      % Convert back to a column vector if necessary
      if was_vector
        out = reshape(out,numel(out),1);
      end
      
    end
    
    function [mf_resp,range_axis] = matchedFilterResponse(obj,data)
      
      % Calculate the matched filter response of the given input data using
      % the waveform object associated with the radar
      %
      % INPUTS:
      %  - data: The fast time data to be filtered. This can be either an
      %          LM x 1 pulse train or an L x M matrix, where L is the
      %          number of fast time samples and M is the number of pulses.
      %
      % OUTPUTS:
      %  - mf_resp: The calculated matched filter response
      %  - range_axis: The ranges corresponding to each delay in the
      %                matched filter output
      
      % Input is a vector. Reshape to a matrix to do the calculations
      if size(data,2) == 1
        data = reshape(data,floor(length(data)/obj.num_pulses),obj.num_pulses);
      end
      
      mf_length = size(obj.waveform.data,1)+size(data,1)-1;
      % Pad the matched filter and data vector (or matrix) to the size of
      % the matched filter output
      waveform_norm = obj.waveform.data ./ norm(obj.waveform.data);
      mf = [flipud(conj(waveform_norm));...
        zeros(mf_length-size(waveform_norm,1),1)];
      data = [data;zeros(mf_length-size(data,1),size(data,2))];
      % Calculate the matched filter output in the frequency domain
      mf_resp = zeros(size(data));
      for ii = 1:size(data,2)
        mf_resp(:,ii) = ifft(fft(data(:,ii)).*fft(mf));
      end
      % Calculate the corresponding range axis for the matched filter
      % response, where range 0 corresponds to a sample delay equal to the
      % length of the transmitted waveform
      idx = (1:size(mf_resp,1))';
      time_axis = (idx-length(obj.waveform.data))/obj.waveform.samp_rate;
      range_axis = time_axis*(obj.const.c/2);
      
    end
    
    function [rd_map,velocity_axis] = dopplerProcessing(obj,data,oversampling)
      
      % Perform doppler processing on the matched filtered data
      %
      % INPUTS:
      %  - data: A P x M matrix of matched filter vectors, where P is the
      %          length of the matched filter output and M is the number of
      %          pulses.
      %  - oversampling: The doppler oversampling rate
      %
      % OUTPUTS:
      %  - rd_map: The range doppler map
      %  - velocity_axis: The velocity values of each doppler bin
      
      narginchk(2,3);
      % Set default arguments
      if (nargin == 2)
        oversampling = 1;
      end
      
      % Input is a vector. Reshape to a matrix to do the calculations
      if size(data,2) == 1
        data = reshape(data,floor(length(data)/obj.num_pulses),obj.num_pulses);
      end
      % Perform doppler processing over all the pulses
      rd_map = fftshift(fft(data,obj.num_pulses*oversampling,2),2);
      % Create the doppler axis for the range-doppler map
      velocity_step = 2*obj.velocity_unambig/obj.num_pulses;
      velocity_axis = (-obj.velocity_unambig:velocity_step:...
        obj.velocity_unambig-velocity_step)';
      
    end
    
    function snr = SNR(obj,targets)
      
      % Compute the SNR for each target in the input list
      if (strcmpi(obj.scale,'db'))
        snr = obj.receivedPower(targets) - obj.power_noise;
      else
        snr = obj.receivedPower(targets) / obj.power_noise;
      end
      
    end
    
  end
  
  %% Setter Methods
  methods
    
    function set.num_pulses(obj,val)
      
      validateattributes(val,{'numeric'},{'finite','nonnan','nonnegative'});
      obj.d_num_pulses = val;
      
    end
    
    function set.prf(obj,val)
      
      validateattributes(val,{'numeric'},{'finite','nonnan','nonnegative'});
      obj.d_prf = val;
      obj.d_pri = 1 / obj.d_prf;
      
    end
    
    function set.pri(obj,val)
      
      validateattributes(val,{'numeric'},{'finite','nonnan','nonnegative'});
      obj.d_pri = val;
      obj.d_prf = 1 / obj.d_pri;
      
    end
    
    function set.waveform(obj,val)
      
      validateattributes(val,{'Waveform'},{});
      obj.d_waveform = val;
      
    end
    
    function set.antenna(obj,val)
      
      validateattributes(val,{'AbstractAntenna','AbstractAntennaArray'},{});
      obj.d_antenna = val;
      
    end
    
  end
  
  %% Getter Methods
  methods
    
    function out = get.range_horizon(obj)
      % DEPENDS ON COORDINATE SYSTEM
      out = sqrt(2*obj.const.ae*obj.position(3) + obj.position(3)^2);
    end
    
    function out = get.range_resolution(obj)
      out = obj.const.c/2/obj.bandwidth;
    end
    
    function out = get.num_pulses(obj)
      out = obj.d_num_pulses;
    end
    
    function out = get.prf(obj)
      out = obj.d_prf;
    end
    
    function out = get.pri(obj)
      out = obj.d_pri;
    end
    
    function out = get.waveform(obj)
      out = obj.d_waveform;
    end
    
    function out = get.antenna(obj)
      out = obj.d_antenna;
    end
    
    function out = get.doppler_unambig(obj)
      out = obj.prf/2;
    end
    
    function out = get.range_unambig(obj)
      out = obj.const.c*obj.pri/2;
    end
    
    function out = get.velocity_unambig(obj)
      out = obj.wavelength*obj.prf/4;
    end
  end
  
  %% Static Methods
  methods (Static)
    
    function out = delaySequence(data,delay)
      % Delay the input vector by the given delay
      % INPUTS:
      %  - data: The data to be delayed
      %  - delay: The number of samples to delay the data
      %
      % OUTPUT: The delayed sequence
      delay = round(delay); % Only consider integer sample delays
      delayed_seq_len = size(data,1)+max(0,delay);
      out = zeros(delayed_seq_len,1);
      % Insert the data after the given number of delay samples
      tmp = data;
      out(1+delay:delayed_seq_len) = tmp;
      % Keep the output sequence the same size as the input. All data
      % delayed past the original sequence is truncated.
      out = out(1:length(data),:);
      
    end
    
  end
  
end