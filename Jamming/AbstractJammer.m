% An abstract class representing a jammer

classdef (Abstract) AbstractJammer < matlab.mixin.Copyable & matlab.mixin.CustomDisplay
  
  
  % Private properties
  properties (Access = protected)
    % A list of antenna parameters that are angles, used when switching
    % between radian mode and degree mode
    angle_quantities = {'azimuth','elevation'};
    power_quantities = {};
    voltage_quantities = {};
  end
  
  properties (Dependent)
    
    angle_unit;
    scale;
    azimuth;
    elevation;
    range;
    
  end
  
  properties (Access = protected)
    
    d_angle_unit = 'Radians';
    d_scale = 'dB';
    d_azimuth;
    d_elevation;
    d_range;
    
  end
  
  %% Public Methods
  methods
    function [Rj,Aj] = covariance(obj,radar)
      
      % Compute the clairvoyant clutter covariance matrix using eq. (64) of
      % the ward report, assuming zero velocity misalignment
      
      % Create copies of the inputs to avoid accidentally changing things
      jammer = copy(obj);
      radar = copy(radar);
      [jammer.scale] = deal('Linear');
      [jammer.angle_unit] = deal('Radians');
      radar.scale = 'Linear';
      % Spatial frequency for steering vector computation
      freq_spatial = radar.antenna.spacing_element/radar.wavelength*...
        cos([jammer.elevation]).*sin([jammer.azimuth]);
      N = radar.antenna.num_elements; % Number of array elements
      M = radar.num_pulses;     % Number of pulses
      Nj = numel(jammer);       % Number of clutter patches in ring
      Aj = zeros(N, Nj);            % Space-time steering vector
      % Compute the spatial steering vector for each jammer and store them
      % in the columns of Aj
      % TODO: Perform this computation without loops using meshgrid
      for ii = 1:Nj
        Aj(:,ii) = exp(1i*2*pi*freq_spatial(ii)*(0:N-1));
      end
      % J x J jammer source covariance matrix
      jam_source_cov = diag(radar.JNR(jammer));
      % N x J jammer spatial covariance matrix
      spatial_cov = Aj*jam_source_cov*Aj';
      % Complete space-time covariance matrix (assumes jammers are
      % uncorrelated in time)
      Rj = kron(eye(M),spatial_cov);
      
      
    end
  end
  
  %% Setter Methods
  methods
    
    function set.azimuth(obj,val)
      validateattributes(val,{'numeric'},{'finite','nonnan'});
      obj.d_azimuth = val;
    end
    
    function set.elevation(obj,val)
      validateattributes(val,{'numeric'},{'finite','nonnan'});
      obj.d_elevation = val;
    end
    
    function set.range(obj,val)
      validateattributes(val,{'numeric'},{'finite','nonnan','nonnegative'});
      obj.d_range = val;
    end
    
    function set.scale(obj,val)
      
      validateattributes(val,{'string','char'},{});
      if strncmpi(val,'linear',1) && ~strncmpi(obj.scale,'Linear',1)
        % Change all voltage/power quantities to linear scale
        obj.convertToLinear();
        obj.d_scale = 'Linear';
      elseif strncmpi(val,'db',1) && ~strncmpi(obj.scale,'dB',1)
        % Change all voltage/power quantities to dB scale
        obj.convertTodB();
        obj.d_scale = 'dB';
      end
      
    end
    
    function set.angle_unit(obj,val)
      
      validateattributes(val,{'string','char'},{});
      if strncmpi(val,'Degrees',1) && ~strncmpi(obj.angle_unit,'Degrees',1)
        % Convert angle measures to degree
        obj.d_angle_unit = 'Degrees';
        obj.convertToDegree();
      elseif strncmpi(val,'Radians',1) && ~strncmpi(obj.angle_unit,'Radians',1)
        % Convert angle measures to radians
        obj.d_angle_unit = 'Radians';
        obj.convertToRadian();
      end
      
    end
    
  end
  
  %% Setter Methods
  methods
    function out = get.angle_unit(obj)
      out = obj.d_angle_unit;
    end
    
    function out = get.scale(obj)
      out = obj.d_scale;
    end
    
    function out = get.azimuth(obj)
      out = obj.d_azimuth;
    end
    
    function out = get.elevation(obj)
      out = obj.d_elevation;
    end
    
    function out = get.range(obj)
      out = obj.d_range;
    end
    
  end
  %% Private Methods
  methods
    
    % Convert all parameters that are currently in linear units to dB
    function convertTodB(obj)
      for ii = 1:numel(obj.power_quantities)
        obj.(obj.power_quantities{ii}) = 10*log10(obj.(obj.power_quantities{ii}));
      end
      for ii = 1:numel(obj.voltage_quantities)
        obj.(obj.voltage_quantities{ii}) = 20*log10(obj.(obj.voltage_quantities{ii}));
      end
    end
    
    % Convert all parameters that are currently in dB to linear units
    function convertToLinear(obj)
      
      for ii = 1:numel(obj.power_quantities)
        obj.(obj.power_quantities{ii}) = 10^(obj.(obj.power_quantities{ii})/10);
      end
      
      for ii = 1:numel(obj.voltage_quantities)
        obj.(obj.voltage_quantities{ii}) = 10^(obj.(obj.voltage_quantities{ii})/20);
      end
      
    end
    
    % Convert all angle measures to degree
    function convertToDegree(obj)
      
      for ii = 1:numel(obj.angle_quantities)
        obj.(obj.angle_quantities{ii}) = (180/pi)*obj.(obj.angle_quantities{ii});
      end
      
    end
    
    % Convert all angle measures to radians
    function convertToRadian(obj)
      
      for ii = 1:numel(obj.angle_quantities)
        obj.(obj.angle_quantities{ii}) = (pi/180)*obj.(obj.angle_quantities{ii});
      end
      
    end
    
  end % Private methods
  
  %% Hidden Methods (DO NOT EDIT THESE)
  methods (Hidden)
    
    function value = properties( obj )
      % Put the properties list in sorted order
      propList = sort( builtin("properties", obj) );
      % Move any control switch parameters to the top of the output
      switches = {'scale', 'const'}';
      propList(ismember(propList,switches)) = [];
      propList = cat(1,switches,propList);
      if nargout == 0
        disp(propList);
      else
        value = propList;
      end
    end
    
    function value = fieldnames( obj )
      value = sort( builtin( "fieldnames", obj ) );
    end
  end
  
  methods (Access = protected)
    
    function group = getPropertyGroups( obj )
      props = properties( obj );
      group = matlab.mixin.util.PropertyGroup( props );
    end
    
  end
end