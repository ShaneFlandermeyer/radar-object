% An abstract class representing a jammer

classdef (Abstract) AbstractJammer < matlab.mixin.Copyable & matlab.mixin.CustomDisplay
    
    
    % Private properties
    properties (Access = protected)
        % A list of antenna parameters that are angles, used when switching
        % between radian mode and degree mode
        angleQuantities = {'azimuth','elevation'};
        powerQuantities = {};
        voltageQuantities = {};
    end
    
    properties (Dependent)
        
        angleUnit;
        scale;
        azimuth;
        elevation;
        range;
        position;
        
    end
    
    properties (Access = protected)
        
        d_angleUnit = 'Radians';
        d_scale = 'dB';
        d_azimuth;
        d_elevation;
        d_range;
        d_position;
        
    end
    
    %% Public Methods
    methods
        
        function jnr = JNR(obj,radar)
            % Calculate the JNR (per element, per pulse) for the given array of
            % jammer objects
            
            if ~isa(obj,'BarrageJammer')
                error('Calculation currently only supported for barrage jammers')
            end
            
            % Convert the copied objects to linear units and radian angles
            radar = copy(radar);
            jammer = copy(obj);
            radar.scale = 'Linear';
            radar.antenna.angleUnit = 'Radians';
            [jammer.angleUnit] = deal('Radians');
            % Receive element gain. Since the JNR is per element, we do not include
            % the Re
            g = radar.antenna.elements(1,1).normPowerGain([jammer.azimuth],[jammer.elevation])*...
                radar.antenna.elementGain;
            % Jammer power
            J0 = [jammer.effRadiatedPower]*radar.bandwidth.*g*radar.wavelength^2 ./ ...
                ((4*pi)^2*[jammer.range].^2*radar.systemLoss);
            % JNR
            jnr = J0.'/radar.noisePower;
            
            for ii = 1:length(jammer)
                if strcmpi(jammer(ii).scale,'dB')
                    jnr(ii) = 10*log10(jnr(ii));
                end
            end
            
            
        end
        
        function [Rj,Aj] = covariance(obj,radar)
            
            % Compute the clairvoyant clutter covariance matrix using eq. (64) of
            % the ward report, assuming zero velocity misalignment
            
            % Create copies of the inputs to avoid accidentally changing things
            jammer = copy(obj);
            radar = copy(radar);
            [jammer.scale] = deal('Linear');
            [jammer.angleUnit] = deal('Radians');
            radar.scale = 'Linear';
            % Spatial frequency for steering vector computation
            freq_spatial = radar.antenna.elementSpacing/radar.wavelength*...
                cos([jammer.elevation]).*sin([jammer.azimuth]);
            % Compute the spatial steering vector for each jammer and store them
            % in the columns of Aj
            Aj = radar.antenna.spatialSteeringVector(freq_spatial);
            % J x J jammer source covariance matrix
            jam_source_cov = radar.noisePower*diag(jammer.JNR(radar));
            % N x J jammer spatial covariance matrix
            spatial_cov = Aj*jam_source_cov*Aj';
            % Complete space-time covariance matrix (assumes jammers are
            % uncorrelated in time)
            Rj = kron(eye(radar.nPulses),spatial_cov);
            
        end
        
    end
    
    %% Setter Methods
    methods
        
        function set.position(obj,val)
            % Should be a 3D vector
            validateattributes(val,{'numeric'},...
                {'vector','3d','finite','nonnan'});
            % If we're given a row vector, convert it to column
            if (isrow(val))
                val = val.';
            end
            obj.d_position = val;
        end
        
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
        
        function set.angleUnit(obj,val)
            
            validateattributes(val,{'string','char'},{});
            if strncmpi(val,'Degrees',1) && ~strncmpi(obj.angleUnit,'Degrees',1)
                % Convert angle measures to degree
                obj.d_angleUnit = 'Degrees';
                obj.convertToDegree();
            elseif strncmpi(val,'Radians',1) && ~strncmpi(obj.angleUnit,'Radians',1)
                % Convert angle measures to radians
                obj.d_angleUnit = 'Radians';
                obj.convertToRadian();
            end
            
        end
        
    end
    
    %% Getter Methods
    methods
        
        function out = get.position(obj)
            out = obj.d_position;
        end
        
        function out = get.angleUnit(obj)
            out = obj.d_angleUnit;
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
            for ii = 1:numel(obj.powerQuantities)
                obj.(obj.powerQuantities{ii}) = 10*log10(obj.(obj.powerQuantities{ii}));
            end
            for ii = 1:numel(obj.voltageQuantities)
                obj.(obj.voltageQuantities{ii}) = 20*log10(obj.(obj.voltageQuantities{ii}));
            end
        end
        
        % Convert all parameters that are currently in dB to linear units
        function convertToLinear(obj)
            
            for ii = 1:numel(obj.powerQuantities)
                obj.(obj.powerQuantities{ii}) = 10^(obj.(obj.powerQuantities{ii})/10);
            end
            
            for ii = 1:numel(obj.voltageQuantities)
                obj.(obj.voltageQuantities{ii}) = 10^(obj.(obj.voltageQuantities{ii})/20);
            end
            
        end
        
        % Convert all angle measures to degree
        function convertToDegree(obj)
            
            for ii = 1:numel(obj.angleQuantities)
                obj.(obj.angleQuantities{ii}) = (180/pi)*obj.(obj.angleQuantities{ii});
            end
            
        end
        
        % Convert all angle measures to radians
        function convertToRadian(obj)
            
            for ii = 1:numel(obj.angleQuantities)
                obj.(obj.angleQuantities{ii}) = (pi/180)*obj.(obj.angleQuantities{ii});
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