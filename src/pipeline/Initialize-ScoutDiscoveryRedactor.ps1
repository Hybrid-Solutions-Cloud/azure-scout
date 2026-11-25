#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ScoutDiscoveryRedactorState = $null

<#
.SYNOPSIS
    Compiles the discovery redactor: the same rules as Protect-ScoutDiscoveryValue, in C#.

.DESCRIPTION
    Discovery redacts credential-shaped values in every resource's properties, tags and
    enrichment. The PowerShell implementation is one recursive function call per property node,
    and on a 42-subscription tenant that walk was most of the 2.7-minute discovery build (AB#9300).
    This compiles an equivalent walk once per session, the first time discovery runs (not at module
    import). If compilation is unavailable (for example in constrained language mode), it returns
    $false and Protect-ScoutDiscoveryValue keeps using the PowerShell walk.

    The rules are identical by construction and by test
    (tests/DiscoveryRedactor.Equivalence.Tests.ps1, and a live-data comparison before release):
      - a name is sensitive when, with every character outside [A-Za-z0-9] removed and lower-cased,
        it ends in password, passwd, pwd, secret(s), token(s), sharedkey, privatekey,
        connectionstring(s), accountkey, accesskey, apikey, primarykey, secondarykey, masterkey,
        sastoken or saskey, or equals credential;
      - a value under a sensitive name becomes '[REDACTED]';
      - strings, primitives, decimal, DateTime, DateTimeOffset and Guid are returned as they are;
      - past the maximum depth the value becomes '[REDACTED:MAXIMUM-DEPTH]';
      - in an object whose name is sensitive, or whose type is secureString / secureObject, the
        members value and defaultValue are redacted;
      - dictionaries and objects are copied member by member, lists item by item.
#>
function Initialize-ScoutDiscoveryRedactor {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -ne $script:ScoutDiscoveryRedactorState) { return [bool]$script:ScoutDiscoveryRedactorState }
    if ('AzureScout.DiscoveryRedactor' -as [type]) { $script:ScoutDiscoveryRedactorState = $true; return $true }
    $source = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace AzureScout
{
    public static class DiscoveryRedactor
    {
        private static readonly Regex NonAlphanumeric = new Regex("[^A-Za-z0-9]", RegexOptions.IgnoreCase);
        private static readonly Regex SensitiveSuffix = new Regex("(password|passwd|pwd|secrets?|tokens?|sharedkey|privatekey|connectionstrings?|accountkey|accesskey|apikey|primarykey|secondarykey|masterkey|sastoken|saskey)$", RegexOptions.IgnoreCase);
        private static readonly Regex SecureType = new Regex("^secure(string|object)$", RegexOptions.IgnoreCase);
        private static readonly Dictionary<string, bool> SensitiveCache = new Dictionary<string, bool>(StringComparer.Ordinal);
        private static readonly Dictionary<string, string> NormalizedCache = new Dictionary<string, string>(StringComparer.Ordinal);
        private static readonly object CacheLock = new object();

        public static string Normalize(string name)
        {
            if (name == null) { return string.Empty; }
            lock (CacheLock)
            {
                string value;
                if (NormalizedCache.TryGetValue(name, out value)) { return value; }
                value = NonAlphanumeric.Replace(name, string.Empty).ToLowerInvariant();
                NormalizedCache[name] = value;
                return value;
            }
        }

        public static bool IsSensitive(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) { return false; }
            lock (CacheLock)
            {
                bool cached;
                if (SensitiveCache.TryGetValue(name, out cached)) { return cached; }
            }
            string normalized = Normalize(name);
            bool result = SensitiveSuffix.IsMatch(normalized) || string.Equals(normalized, "credential", StringComparison.OrdinalIgnoreCase);
            lock (CacheLock) { SensitiveCache[name] = result; }
            return result;
        }

        private static object Unwrap(object value)
        {
            PSObject pso = value as PSObject;
            if (pso != null && !(pso.BaseObject is PSCustomObject)) { return pso.BaseObject; }
            return value;
        }

        private static string AsString(object value)
        {
            if (value == null) { return string.Empty; }
            return LanguagePrimitives.ConvertTo<string>(value);
        }

        // Get-ScoutResourceCompletenessValue for a single segment.
        private static object ReadMember(object value, string name)
        {
            if (value == null) { return null; }
            object baseObject = Unwrap(value);
            IDictionary dictionary = baseObject as IDictionary;
            if (dictionary != null)
            {
                foreach (object key in dictionary.Keys)
                {
                    if (string.Equals(AsString(key), name, StringComparison.OrdinalIgnoreCase)) { return dictionary[key]; }
                }
                return null;
            }
            PSPropertyInfo property = PSObject.AsPSObject(value).Properties[name];
            return property == null ? null : property.Value;
        }

        private static void SetMember(PSObject target, string name, object value)
        {
            PSPropertyInfo existing = target.Properties[name];
            if (existing != null) { existing.Value = value; }
            else { target.Properties.Add(new PSNoteProperty(name, value)); }
        }

        private static bool IsValueMember(string name, bool protectContext)
        {
            if (!protectContext) { return false; }
            string normalized = Normalize(name);
            return string.Equals(normalized, "value", StringComparison.OrdinalIgnoreCase) || string.Equals(normalized, "defaultvalue", StringComparison.OrdinalIgnoreCase);
        }

        public static object Protect(object input, string propertyName, int depth, int maximumDepth)
        {
            if (input == null) { return null; }
            if (IsSensitive(propertyName)) { return "[REDACTED]"; }
            object baseObject = Unwrap(input);
            if (baseObject is string || baseObject.GetType().IsPrimitive || baseObject is decimal ||
                baseObject is DateTime || baseObject is DateTimeOffset || baseObject is Guid)
            {
                return input;
            }
            if (depth >= maximumDepth) { return "[REDACTED:MAXIMUM-DEPTH]"; }

            string contextName = AsString(ReadMember(input, "name"));
            string contextType = AsString(ReadMember(input, "type"));
            bool protectContext = IsSensitive(contextName) || SecureType.IsMatch(contextType);

            IDictionary dictionary = baseObject as IDictionary;
            if (dictionary != null)
            {
                PSObject copy = new PSObject();
                foreach (object key in dictionary.Keys)
                {
                    string keyName = AsString(key);
                    if (IsSensitive(keyName) || IsValueMember(keyName, protectContext)) { SetMember(copy, keyName, "[REDACTED]"); }
                    else { SetMember(copy, keyName, Protect(dictionary[key], keyName, depth + 1, maximumDepth)); }
                }
                return copy;
            }

            IEnumerable enumerable = baseObject as IEnumerable;
            if (enumerable != null)
            {
                List<object> items = new List<object>();
                foreach (object item in enumerable) { items.Add(Protect(item, propertyName, depth + 1, maximumDepth)); }
                return items.ToArray();
            }

            List<PSPropertyInfo> properties = new List<PSPropertyInfo>();
            foreach (PSPropertyInfo property in PSObject.AsPSObject(input).Properties)
            {
                PSMemberTypes type = property.MemberType;
                if (type == PSMemberTypes.NoteProperty || type == PSMemberTypes.Property || type == PSMemberTypes.AliasProperty || type == PSMemberTypes.ScriptProperty)
                {
                    properties.Add(property);
                }
            }
            if (properties.Count == 0) { return input; }
            PSObject result = new PSObject();
            foreach (PSPropertyInfo property in properties)
            {
                string name = property.Name ?? string.Empty;
                if (IsSensitive(name) || IsValueMember(name, protectContext)) { SetMember(result, name, "[REDACTED]"); }
                else { SetMember(result, name, Protect(property.Value, name, depth + 1, maximumDepth)); }
            }
            return result;
        }
    }
}
'@
    try {
        Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
        $script:ScoutDiscoveryRedactorState = $true
    }
    catch {
        Write-Verbose "Initialize-ScoutDiscoveryRedactor: compiled redactor unavailable, using the PowerShell walk: $($_.Exception.Message)"
        $script:ScoutDiscoveryRedactorState = $false
    }
    return [bool]$script:ScoutDiscoveryRedactorState
}
