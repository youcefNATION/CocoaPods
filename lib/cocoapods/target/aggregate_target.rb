module Pod
  # Stores the information relative to the target used to cluster the targets
  # of the single Pods. The client targets will then depend on this one.
  #
  class AggregateTarget < Target
    # Initialize a new instance
    #
    # @param [TargetDefinition] target_definition @see target_definition
    # @param [Sandbox] sandbox @see sandbox
    #
    def initialize(target_definition, sandbox)
      @target_definition = target_definition
      @sandbox = sandbox
      @pod_targets = []
      @file_accessors = []
      @xcconfigs = {}
    end

    # @return [String] the label for the target.
    #
    def label
      target_definition.label.to_s
    end

    # @return [String] the name to use for the source code module constructed
    #         for this target, and which will be used to import the module in
    #         implementation source files.
    #
    def product_module_name
      c99ext_identifier(label)
    end

    # @return [Pathname] the folder where the client is stored used for
    #         computing the relative paths. If integrating it should be the
    #         folder where the user project is stored, otherwise it should
    #         be the installation root.
    #
    attr_accessor :client_root

    # @return [Pathname] the path of the user project that this target will
    #         integrate as identified by the analyzer.
    #
    # @note   The project instance is not stored to prevent editing different
    #         instances.
    #
    attr_accessor :user_project_path

    # @return [Array<String>] the list of the UUIDs of the user targets that
    #         will be integrated by this target as identified by the analyzer.
    #
    # @note   The target instances are not stored to prevent editing different
    #         instances.
    #
    attr_accessor :user_target_uuids

    # List all user targets that will be integrated by this #target.
    #
    # @param  [Xcodeproj::Project] project
    #         The project to search for the user targets
    #
    # @return [Array<PBXNativeTarget>]
    #
    def user_targets(project = nil)
      return [] unless user_project_path
      project ||= Xcodeproj::Project.open(user_project_path)
      user_target_uuids.map do |uuid|
        native_target = project.objects_by_uuid[uuid]
        unless native_target
          raise Informative, '[Bug] Unable to find the target with ' \
            "the `#{uuid}` UUID for the `#{self}` integration library"
        end
        native_target
      end
    end

    # @return [Hash<String, Xcodeproj::Config>] Map from configuration name to
    #         configuration file for the target
    #
    # @note   The configurations are generated by the {TargetInstaller} and
    #         used by {UserProjectIntegrator} to check for any overridden
    #         values.
    #
    attr_reader :xcconfigs

    # @return [Array<PodTarget>] The dependencies for this target.
    #
    attr_accessor :pod_targets

    # @param  [String] build_configuration The build configuration for which the
    #         the pod targets should be returned.
    #
    # @return [Array<PodTarget>] the pod targets for the given build
    #         configuration.
    #
    def pod_targets_for_build_configuration(build_configuration)
      pod_targets.select do |pod_target|
        pod_target.include_in_build_config?(build_configuration)
      end
    end

    # @return [Array<Specification>] The specifications used by this aggregate target.
    #
    def specs
      pod_targets.map(&:specs).flatten
    end

    # @return [Hash{Symbol => Array<Specification>}] The pod targets for each
    #         build configuration.
    #
    def specs_by_build_configuration
      result = {}
      user_build_configurations.keys.each do |build_configuration|
        result[build_configuration] = pod_targets_for_build_configuration(build_configuration).
          flat_map(&:specs)
      end
      result
    end

    # @return [Array<Specification::Consumer>] The consumers of the Pod.
    #
    def spec_consumers
      specs.map { |spec| spec.consumer(platform) }
    end

    # @return [Boolean] Whether the target uses Swift code
    #
    def uses_swift?
      pod_targets.any?(&:uses_swift?)
    end

    #-------------------------------------------------------------------------#

    # @!group Support files

    # @return [Pathname] The absolute path of acknowledgements file.
    #
    # @note   The acknowledgements generators add the extension according to
    #         the file type.
    #
    def acknowledgements_basepath
      support_files_dir + "#{label}-acknowledgements"
    end

    # @return [Pathname] The absolute path of the copy resources script.
    #
    def copy_resources_script_path
      support_files_dir + "#{label}-resources.sh"
    end

    # @return [Pathname] The absolute path of the embed frameworks script.
    #
    def embed_frameworks_script_path
      support_files_dir + "#{label}-frameworks.sh"
    end

    # @return [String] The xcconfig path of the root from the `$(SRCROOT)`
    #         variable of the user's project.
    #
    def relative_pods_root
      "${SRCROOT}/#{sandbox.root.relative_path_from(client_root)}"
    end

    # @param  [String] config_name The build configuration name to get the xcconfig for
    # @return [String] The path of the xcconfig file relative to the root of
    #         the user project.
    #
    def xcconfig_relative_path(config_name)
      relative_to_srcroot(xcconfig_path(config_name)).to_s
    end

    # @return [String] The path of the copy resources script relative to the
    #         root of the user project.
    #
    def copy_resources_script_relative_path
      "${SRCROOT}/#{relative_to_srcroot(copy_resources_script_path)}"
    end

    # @return [String] The path of the embed frameworks relative to the
    #         root of the user project.
    #
    def embed_frameworks_script_relative_path
      "${SRCROOT}/#{relative_to_srcroot(embed_frameworks_script_path)}"
    end

    private

    # @!group Private Helpers
    #-------------------------------------------------------------------------#

    # Computes the relative path of a sandboxed file from the `$(SRCROOT)`
    # variable of the user's project.
    #
    # @param  [Pathname] path
    #         A relative path from the root of the sandbox.
    #
    # @return [String] The computed path.
    #
    def relative_to_srcroot(path)
      path.relative_path_from(client_root).to_s
    end
  end
end
